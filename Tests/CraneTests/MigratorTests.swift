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
import Testing

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

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.checksumMismatch(
                id: .apply(version: 1, description: "create_users"),
                description: "migrations/v1.create_users.apply.sql",
                expected: originalChecksum,
                actual: checksum(sqlScript: modifiedScript)
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
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

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.checksumMismatch(
                id: .undo(version: 1, description: "create_users"),
                description: "migrations/v1.create_users.undo.sql",
                expected: originalChecksum,
                actual: checksum(sqlScript: modifiedScript)
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
        }

        @Test func `Executes repeatable migration when checksum changed`() async throws {
            let modifiedScript = "CREATE OR REPLACE VIEW active_users AS SELECT * FROM users WHERE deleted_at IS NULL;"

            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews(script: modifiedScript)
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Repeatable.refreshViews()])

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [modifiedScript])
        }

        @Test func `Skips repeatable migration when checksum unchanged`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews()
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Repeatable.refreshViews()])

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()

            #expect(await target.executedSQLScripts.isEmpty)
        }

        @Test func `Executes repeatable migration when never applied`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Repeatable.refreshViews()
                ]
            )
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.createOrReplaceActiveUsersView])
        }

        @Test func `Executes pending versioned migration`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(),
                    ResolvedMigration.Apply.addEmailToUsersTable(),
                ]
            )
            let target = MockTarget(history: [SchemaHistoryRow.Apply.createUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.addEmailToUsersTable])
        }

        @Test func `Does not execute undo migrations`() async throws {
            let resolver = MockResolver(
                migrations: [
                    ResolvedMigration.Apply.createUsersTable(),
                    ResolvedMigration.Undo.dropUsersTable(),
                ]
            )
            let target = MockTarget()

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()

            #expect(await target.executedSQLScripts == [SQLScriptStub.createUsersTable])
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

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingMigration(
                version: 1,
                type: .apply,
                description: "migrations/v1.create_users.apply.sql"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
        }

        @Test func `Throws validation error when undo migration is missing`() async throws {
            let resolver = MockResolver(migrations: [])
            let target = MockTarget(history: [SchemaHistoryRow.Undo.dropUsersTable()])

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingMigration(
                version: 1,
                type: .undo,
                description: "migrations/v1.create_users.undo.sql"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
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
                        description: "migrations/repeat.refresh_views.sql",
                        type: .repeatable,
                        checksum: checksum(sqlScript: "SELECT VERSION();"),
                        user: "mock_user",
                        executionDate: .stub,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.repeatableMigrationWithVersion(
                version: 42,
                description: "migrations/repeat.refresh_views.sql"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
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
                        description: "migrations/v1.create_users.apply.sql",
                        type: .apply,
                        checksum: checksum(sqlScript: SQLScriptStub.createUsersTable),
                        user: "mock_user",
                        executionDate: .stub,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingVersion(
                type: .apply,
                description: "migrations/v1.create_users.apply.sql"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
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
                        description: "migrations/v1.create_users.undo.sql",
                        type: .undo,
                        checksum: checksum(sqlScript: SQLScriptStub.dropUsersTable),
                        user: "mock_user",
                        executionDate: .stub,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ]
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            let expectedError = Crane.Migrator<MockTarget>.ValidationError.missingVersion(
                type: .undo,
                description: "migrations/v1.create_users.undo.sql"
            )
            await #expect(throws: expectedError) {
                try await migrator.apply()
            }
        }
    }
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
        description: String,
        checksum: String,
        user: String = "mock_user",
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
            description: description,
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
            script: String = SQLScriptStub.createUsersTable
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .apply(version: 1, description: "create_users"),
                description: "migrations/v1.create_users.apply.sql",
                sqlScript: { script }
            )
        }

        static func addEmailToUsersTable(
            script: String = SQLScriptStub.addEmailToUsersTable
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .apply(version: 2, description: "add_email"),
                description: "migrations/v2.add_email.apply.sql",
                sqlScript: { script }
            )
        }
    }

    fileprivate enum Undo {
        static func dropUsersTable(
            script: String = SQLScriptStub.dropUsersTable
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .undo(version: 1, description: "create_users"),
                description: "migrations/v1.create_users.undo.sql",
                sqlScript: { script }
            )
        }
    }

    fileprivate enum Repeatable {
        static func refreshViews(
            script: String = SQLScriptStub.createOrReplaceActiveUsersView
        ) -> ResolvedMigration {
            ResolvedMigration(
                id: .repeatable(description: "refresh_views"),
                description: "migrations/repeat.refresh_views.sql",
                sqlScript: { script }
            )
        }
    }
}

extension SchemaHistoryRow {
    fileprivate enum Apply {
        static func createUsersTable(
            rank: Int = 1,
            user: String = "mock_user",
            executionDate: Date = .stub,
            duration: Duration = .milliseconds(42)
        ) -> SchemaHistoryRow {
            SchemaHistoryRow(
                id: .apply(version: 1, description: "create_users"),
                rank: rank,
                description: "migrations/v1.create_users.apply.sql",
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
                description: "migrations/v2.add_email.apply.sql",
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
                description: "migrations/v1.create_users.undo.sql",
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
                description: "migrations/repeat.refresh_views.sql",
                checksum: Crane.checksum(sqlScript: SQLScriptStub.createOrReplaceActiveUsersView),
                user: user,
                executionDate: executionDate,
                duration: duration
            )
        }
    }
}
