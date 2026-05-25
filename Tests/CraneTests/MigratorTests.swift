//===----------------------------------------------------------------------===//
//
// This source file is part of the Crane open source project
//
// Copyright (c) 2025 the Crane project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crane
import InMemoryLogging
import Logging
import Testing

#if Configuration
import Configuration
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct Migrator {
    @Test func `Defaults to file system resolver`() async throws {
        try await withTemporaryDirectories("migrations") { rootURL, urls in
            let migrationsURL = try #require(urls.first)
            let script = SQLScriptStub.createUsersTable
            try script.write(
                to: migrationsURL.appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            let target = MockTarget()
            let migrator = try Crane.Migrator(
                rootPath: rootURL.path,
                paths: ["migrations"],
                target: target
            )

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [script])
        }
    }

    @Suite struct Apply {
        let logHandler = InMemoryLogHandler()
        let logger: Logger

        init() {
            var logger = Logger(label: "Crane")
            logger.handler = logHandler
            logger.logLevel = .trace
            self.logger = logger
        }

        @Test func `Performs all operations within the target lock`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        script: "v1.create_users.apply.sql",
                        sqlScript: { SQLScriptStub.createUsersTable }
                    )
                ]
            )
            let target = MockTarget()
            #expect(await target.lockCount == 0)

            let migrator = Crane.Migrator(resolver: resolver, target: target)
            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.createUsersTable])
            #expect(await target.lockCount == 1)
            #expect(await target.activeLockCountWhileSettingUpHistory == 1)
            #expect(await target.activeLockCountWhileReadingHistory == 1)
            #expect(await target.activeLockCountWhileReadingCurrentUser == 1)
            #expect(await target.activeLockCountWhileOpeningTransaction == 1)
            #expect(await target.activeLockCountWhileExecutingScript == 1)
            #expect(await target.activeLockCountWhileRecordingRow == 1)
        }

        @Test func `Sets up history before executing migrations`() async throws {
            let resolver = MockResolver(migrations: [])
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target)
            try await migrator.apply()

            #expect(await target.setUpHistoryCallCount == 1)
        }

        @Test func `Succeeds when no migrations are pending`() async throws {
            let resolver = MockResolver(migrations: [])
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)
            try await migrator.apply()

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(level: .info, message: "No pending migrations.", metadata: [:])
                ]
            )
        }

        @Test func `Validates checksums of previously executed versioned migrations`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(),
                    ResolvedMigration.Undo.dropUsersTable(),
                ]
            )
            let target = MockTarget(
                history: [
                    SchemaHistoryRow.Apply.createUsersTable(),
                    SchemaHistoryRow.Undo.dropUsersTable(),
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()
        }

        @Test func `Throws validation error when apply migration checksum mismatches`() async throws {
            let originalScript = "CREATE TABLE users (id UUID PRIMARY KEY);"
            let modifiedScript = "CREATE TABLE users (id UUID PRIMARY KEY, email TEXT NOT NULL);"
            let originalChecksum = checksum(sqlScript: originalScript)

            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(script: modifiedScript)
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Apply.createUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.checksumMismatch(
                id: .apply(version: 1, description: "create_users"),
                script: "migrations/v1.create_users.apply.sql",
                expected: originalChecksum,
                actual: checksum(sqlScript: modifiedScript)
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Migration file has been modified after being applied.",
                        metadata: ["script": "migrations/v1.create_users.apply.sql"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }

        @Test func `Throws validation error when undo migration checksum mismatches`() async throws {
            let originalScript = "DROP TABLE users;"
            let modifiedScript = "DROP TABLE IF EXISTS users;"
            let originalChecksum = checksum(sqlScript: originalScript)

            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Undo.dropUsersTable(script: modifiedScript)
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Undo.dropUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.checksumMismatch(
                id: .undo(version: 1, description: "create_users"),
                script: "migrations/v1.create_users.undo.sql",
                expected: originalChecksum,
                actual: checksum(sqlScript: modifiedScript)
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Migration file has been modified after being applied.",
                        metadata: ["script": "migrations/v1.create_users.undo.sql"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }

        @Test func `Executes repeatable migration when checksum changed`() async throws {
            let modifiedScript = "CREATE OR REPLACE VIEW active_users AS SELECT * FROM users WHERE deleted_at IS NULL;"

            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews(script: modifiedScript)
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Repeatable.refreshViews()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [modifiedScript])

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied migration.",
                        metadata: ["type": "REPEATABLE", "description": "refresh_views"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied pending migrations.",
                        metadata: ["count": "1"]
                    ),
                ]
            )
        }

        @Test func `Skips repeatable migration when checksum unchanged`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews()
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Repeatable.refreshViews()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            try await migrator.apply()

            #expect(await target.executedSQLScripts.isEmpty)

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(level: .info, message: "No pending migrations.", metadata: [:])
                ]
            )
        }

        @Test func `Skips moved repeatable migration when checksum unchanged`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews(path: "migrations/repeatable/repeat.refresh_views.sql")
                ]
            )
            let target = MockTarget(
                history: [SchemaHistoryRow.Repeatable.refreshViews()]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            try await migrator.apply()

            #expect(await target.executedSQLScripts.isEmpty)

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(level: .info, message: "No pending migrations.", metadata: [:])
                ]
            )
        }

        @Test func `Executes repeatable migration when never applied`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews()
                ]
            )
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.createOrReplaceActiveUsersView])

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied migration.",
                        metadata: ["type": "REPEATABLE", "description": "refresh_views"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied pending migrations.",
                        metadata: ["count": "1"]
                    ),
                ]
            )
        }

        @Test func `Executes pending versioned migration`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(),
                    ResolvedMigration.Apply.addEmailToUsersTable(),
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Apply.createUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.addEmailToUsersTable])

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied migration.",
                        metadata: ["type": "APPLY", "description": "add_email", "version": "2"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied pending migrations.",
                        metadata: ["count": "1"]
                    ),
                ]
            )
        }

        @Test func `Does not execute undo migrations`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(),
                    ResolvedMigration.Undo.dropUsersTable(),
                ]
            )
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.createUsersTable])

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied migration.",
                        metadata: ["type": "APPLY", "description": "create_users", "version": "1"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .info,
                        message: "Applied pending migrations.",
                        metadata: ["count": "1"]
                    ),
                ]
            )
        }

        @Suite struct `History recording` {
            @Test func `Records executed versioned migration`() async throws {
                let resolver = MockResolver(
                    migrations: [
                        ResolvedMigration.Apply.createUsersTable()
                    ]
                )
                let target = MockTarget()

                let migrator = Crane.Migrator(
                    resolver: resolver,
                    target: target,
                    measure: {
                        try await $0()
                        return .milliseconds(42)
                    },
                    now: { .stub }
                )
                try await migrator.apply()

                #expect(
                    await target.recordedRows == [
                        SchemaHistoryRow.Apply.createUsersTable()
                    ]
                )
            }

            @Test func `Records nil user when target returns no current user`() async throws {
                let resolver = MockResolver(
                    migrations: [
                        ResolvedMigration.Apply.createUsersTable()
                    ]
                )
                let target = MockTarget(currentUser: nil)

                let migrator = Crane.Migrator(
                    resolver: resolver,
                    target: target,
                    measure: {
                        try await $0()
                        return .milliseconds(42)
                    },
                    now: { .stub }
                )
                try await migrator.apply()

                #expect(
                    await target.recordedRows == [
                        SchemaHistoryRow.Apply.createUsersTable(user: nil)
                    ]
                )
            }

            @Test func `Records executed repeatable migration`() async throws {
                let resolver = MockResolver(
                    migrations: [
                        ResolvedMigration.Repeatable.refreshViews()
                    ]
                )
                let target = MockTarget()

                let migrator = Crane.Migrator(
                    resolver: resolver,
                    target: target,
                    measure: {
                        try await $0()
                        return .milliseconds(42)
                    },
                    now: { .stub }
                )
                try await migrator.apply()

                #expect(
                    await target.recordedRows == [
                        SchemaHistoryRow.Repeatable.refreshViews()
                    ]
                )
            }

            @Test func `Does not record already applied migration`() async throws {
                let resolver = MockResolver(
                    migrations: [
                        ResolvedMigration.Apply.createUsersTable()
                    ]
                )
                let target = MockTarget(history: [SchemaHistoryRow.Apply.createUsersTable()])

                let migrator = Crane.Migrator(resolver: resolver, target: target)
                try await migrator.apply()

                #expect(await target.recordedRows.isEmpty)
            }

            @Test func `Records multiple migrations with incrementing ranks`() async throws {
                let resolver = MockResolver(
                    migrations: [
                        ResolvedMigration.Apply.createUsersTable(),
                        ResolvedMigration.Apply.addEmailToUsersTable(),
                        ResolvedMigration.Repeatable.refreshViews(),
                    ]
                )
                let target = MockTarget()

                let migrator = Crane.Migrator(
                    resolver: resolver,
                    target: target,
                    measure: {
                        try await $0()
                        return .milliseconds(42)
                    },
                    now: { .stub }
                )
                try await migrator.apply()

                #expect(
                    await target.recordedRows == [
                        SchemaHistoryRow.Apply.createUsersTable(),
                        SchemaHistoryRow.Apply.addEmailToUsersTable(),
                        SchemaHistoryRow.Repeatable.refreshViews(rank: 3),
                    ]
                )
            }

            @Test func `Continues rank from existing history`() async throws {
                let resolver = MockResolver(
                    migrations: [
                        ResolvedMigration.Apply.createUsersTable(),
                        ResolvedMigration.Apply.addEmailToUsersTable(),
                    ]
                )
                let target = MockTarget(history: [SchemaHistoryRow.Apply.createUsersTable()])

                let migrator = Crane.Migrator(
                    resolver: resolver,
                    target: target,
                    measure: {
                        try await $0()
                        return .milliseconds(42)
                    },
                    now: { .stub }
                )
                try await migrator.apply()

                #expect(
                    await target.recordedRows == [
                        SchemaHistoryRow.Apply.addEmailToUsersTable()
                    ]
                )
            }
        }

        @Test func `Wraps each migration in a transaction`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(),
                    ResolvedMigration.Apply.addEmailToUsersTable(),
                ]
            )
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target)
            try await migrator.apply()

            #expect(await target.transactionCount == 2)
        }

        @Test func `Throws validation error when apply migration is missing`() async throws {
            let resolver = MockResolver(migrations: [])
            let target = MockTarget(history: [SchemaHistoryRow.Apply.createUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingMigration(
                version: 1,
                type: .apply,
                description: "create_users"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Applied migration is no longer resolved.",
                        metadata: ["type": "APPLY", "description": "create_users", "version": "1"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }

        @Test func `Throws validation error when undo migration is missing`() async throws {
            let resolver = MockResolver(migrations: [])
            let target = MockTarget(history: [SchemaHistoryRow.Undo.dropUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingMigration(
                version: 1,
                type: .undo,
                description: "create_users"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Applied migration is no longer resolved.",
                        metadata: ["type": "UNDO", "description": "create_users", "version": "1"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }

        @Test func `Throws validation error when repeatable migration has version`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews()
                ]
            )
            let target = MockTarget(
                history: [
                    SchemaHistoryRow(
                        rank: 1,
                        version: 42,
                        description: "refresh_views",
                        type: .repeatable,
                        checksum: checksum(sqlScript: "SELECT VERSION();"),
                        user: "mock_user",
                        executionDate: .stub,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.repeatableMigrationWithVersion(
                version: 42,
                description: "refresh_views"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Repeatable schema history row has a version.",
                        metadata: ["description": "refresh_views", "version": "42"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }

        @Test func `Throws validation error when apply migration has no version`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable()
                ]
            )
            let target = MockTarget(
                history: [
                    SchemaHistoryRow(
                        rank: 1,
                        version: nil,
                        description: "create_users",
                        type: .apply,
                        checksum: checksum(sqlScript: SQLScriptStub.createUsersTable),
                        user: "mock_user",
                        executionDate: .stub,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingVersion(
                type: .apply,
                description: "create_users"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Schema history row is missing a version.",
                        metadata: ["type": "APPLY", "description": "create_users"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }

        @Test func `Throws validation error when undo migration has no version`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Undo.dropUsersTable()
                ]
            )
            let target = MockTarget(
                history: [
                    SchemaHistoryRow(
                        rank: 1,
                        version: nil,
                        description: "create_users",
                        type: .undo,
                        checksum: checksum(sqlScript: SQLScriptStub.dropUsersTable),
                        user: "mock_user",
                        executionDate: .stub,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target, logger: logger)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingVersion(
                type: .undo,
                description: "create_users"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }

            #expect(
                logHandler.entries == [
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Schema history row is missing a version.",
                        metadata: ["type": "UNDO", "description": "create_users"]
                    ),
                    InMemoryLogHandler.Entry(
                        level: .error,
                        message: "Failed to apply pending migrations.",
                        metadata: [:]
                    ),
                ]
            )
        }
    }

    #if Configuration
    @Suite struct `Config Reader` {
        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
        @Test func `Reads rootPath and paths from config reader`() async throws {
            let script = SQLScriptStub.createUsersTable

            try await withTemporaryDirectories("sql") { rootURL, urls in
                let sqlURL = try #require(urls.first)
                try script.write(
                    to: sqlURL.appendingPathComponent("v1.create_users.apply.sql"),
                    atomically: true,
                    encoding: .utf8
                )

                let reader = ConfigReader(
                    provider: InMemoryProvider(values: [
                        "rootPath": ConfigValue(.string(rootURL.path), isSecret: false),
                        "paths": ConfigValue(.stringArray(["sql"]), isSecret: false),
                    ])
                )
                let target = MockTarget()
                let migrator = try Crane.Migrator(reader: reader, target: target)

                try await migrator.apply()

                #expect(await target.executedSQLScripts == [script])
            }
        }
    }
    #endif
}

private struct MockResolver: MigrationResolver {
    let migrationsResult: Result<[ResolvedMigration], any Error>

    init(migrations: [ResolvedMigration]) {
        self.migrationsResult = .success(migrations)
    }

    func migrations() async throws -> [ResolvedMigration] {
        try migrationsResult.get()
    }
}

extension Date {
    fileprivate static let stub = Date(timeIntervalSince1970: 42)
}

extension SchemaHistoryRow {
    /// Creates a history row with sensible defaults for fields that are typically irrelevant in tests.
    fileprivate init(
        id: MigrationID,
        rank: Int = 1,
        checksum: String,
        user: String? = "mock_user",
        executionDate: Date = .stub,
        duration: Duration = .milliseconds(42),
        succeeded: Bool = true
    ) {
        let version: Int?
        let type: MigrationType
        switch id {
        case .apply(let v, _):
            version = v
            type = .apply
        case .undo(let v, _):
            version = v
            type = .undo
        case .repeatable:
            version = nil
            type = .repeatable
        }
        self.init(
            rank: rank,
            version: version,
            description: id.description,
            type: type,
            checksum: checksum,
            user: user,
            executionDate: executionDate,
            duration: duration,
            succeeded: succeeded
        )
    }
}

private enum SQLScriptStub {
    static let createUsersTable = "CREATE TABLE users (id UUID PRIMARY KEY);"
    static let addEmailToUsersTable = "ALTER TABLE users ADD COLUMN email TEXT NOT NULL;"
    static let dropUsersTable = "DROP TABLE users;"
    static let createOrReplaceActiveUsersView = """
        CREATE OR REPLACE VIEW active_users AS SELECT * FROM users WHERE active = true;
        """
}

extension ResolvedMigration {
    fileprivate enum Apply {
        static func createUsersTable(
            script: String = SQLScriptStub.createUsersTable,
            path: String = "migrations/v1.create_users.apply.sql"
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .apply(version: 1, description: "create_users"),
                script: path,
                sqlScript: { script }
            )
        }

        static func addEmailToUsersTable(
            script: String = SQLScriptStub.addEmailToUsersTable,
            path: String = "migrations/v2.add_email.apply.sql"
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .apply(version: 2, description: "add_email"),
                script: path,
                sqlScript: { script }
            )
        }
    }

    fileprivate enum Undo {
        static func dropUsersTable(
            script: String = SQLScriptStub.dropUsersTable,
            path: String = "migrations/v1.create_users.undo.sql"
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .undo(version: 1, description: "create_users"),
                script: path,
                sqlScript: { script }
            )
        }
    }

    fileprivate enum Repeatable {
        static func refreshViews(
            script: String = SQLScriptStub.createOrReplaceActiveUsersView,
            path: String = "migrations/repeat.refresh_views.sql"
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .repeatable(description: "refresh_views"),
                script: path,
                sqlScript: { script }
            )
        }
    }
}

extension SchemaHistoryRow {
    fileprivate enum Apply {
        static func createUsersTable(
            rank: Int = 1,
            user: String? = "mock_user",
            executionDate: Date = .stub,
            duration: Duration = .milliseconds(42)
        ) -> SchemaHistoryRow {
            SchemaHistoryRow(
                id: .apply(version: 1, description: "create_users"),
                rank: rank,
                checksum: Crane.checksum(sqlScript: SQLScriptStub.createUsersTable),
                user: user,
                executionDate: executionDate,
                duration: duration
            )
        }

        static func addEmailToUsersTable(
            rank: Int = 2,
            user: String = "mock_user",
            executionDate: Date = .stub,
            duration: Duration = .milliseconds(42)
        ) -> SchemaHistoryRow {
            SchemaHistoryRow(
                id: .apply(version: 2, description: "add_email"),
                rank: rank,
                checksum: Crane.checksum(sqlScript: SQLScriptStub.addEmailToUsersTable),
                user: user,
                executionDate: executionDate,
                duration: duration
            )
        }
    }

    fileprivate enum Undo {
        static func dropUsersTable(
            rank: Int = 2,
            user: String = "mock_user",
            executionDate: Date = .stub,
            duration: Duration = .milliseconds(42)
        ) -> SchemaHistoryRow {
            SchemaHistoryRow(
                id: .undo(version: 1, description: "create_users"),
                rank: rank,
                checksum: Crane.checksum(sqlScript: SQLScriptStub.dropUsersTable),
                user: user,
                executionDate: executionDate,
                duration: duration
            )
        }
    }

    fileprivate enum Repeatable {
        static func refreshViews(
            rank: Int = 1,
            user: String = "mock_user",
            executionDate: Date = .stub,
            duration: Duration = .milliseconds(42)
        ) -> SchemaHistoryRow {
            SchemaHistoryRow(
                id: .repeatable(description: "refresh_views"),
                rank: rank,
                checksum: Crane.checksum(sqlScript: SQLScriptStub.createOrReplaceActiveUsersView),
                user: user,
                executionDate: executionDate,
                duration: duration
            )
        }
    }
}
