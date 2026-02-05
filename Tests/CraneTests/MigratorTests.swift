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
    @Suite struct Apply {
        @Test func `Validates checksums of previously executed versioned migrations`() async throws {
            let applyScript = "CREATE TABLE users (id UUID PRIMARY KEY);"
            let undoScript = "DROP TABLE users;"

            let resolver = MockResolver(
                migrationsResult: .success([
                    ResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.apply.sql",
                        sqlScript: { applyScript }
                    ),
                    ResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.undo.sql",
                        sqlScript: { undoScript }
                    ),
                ])
            )
            let target = MockTarget(
                historyResult: .success([
                    SchemaHistoryRow(
                        id: .apply(version: 1, description: "create_users"),
                        rank: 1,
                        description: "migrations/v1.create_users.apply.sql",
                        checksum: checksum(sqlScript: applyScript),
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    ),
                    SchemaHistoryRow(
                        id: .undo(version: 1, description: "create_users"),
                        rank: 2,
                        description: "migrations/v1.create_users.undo.sql",
                        checksum: checksum(sqlScript: undoScript),
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    ),
                ])
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            try await migrator.apply()
        }

        @Test func `Throws validation error when apply migration checksum mismatches`() async throws {
            let originalScript = "CREATE TABLE users (id UUID PRIMARY KEY);"
            let modifiedScript = "CREATE TABLE users (id UUID PRIMARY KEY, email TEXT NOT NULL);"
            let originalChecksum = checksum(sqlScript: originalScript)

            let resolver = MockResolver(
                migrationsResult: .success([
                    ResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.apply.sql",
                        sqlScript: { modifiedScript }
                    )
                ])
            )
            let target = MockTarget(
                historyResult: .success([
                    SchemaHistoryRow(
                        id: .apply(version: 1, description: "create_users"),
                        rank: 1,
                        description: "migrations/v1.create_users.apply.sql",
                        checksum: originalChecksum,
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ])
            )

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
                migrationsResult: .success([
                    ResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.undo.sql",
                        sqlScript: { modifiedScript }
                    )
                ])
            )
            let target = MockTarget(
                historyResult: .success([
                    SchemaHistoryRow(
                        id: .undo(version: 1, description: "create_users"),
                        rank: 1,
                        description: "migrations/v1.create_users.undo.sql",
                        checksum: originalChecksum,
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ])
            )

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

        @Test func `Allows repeatable migration script changes`() async throws {
            let originalScript = "CREATE OR REPLACE VIEW active_users AS SELECT * FROM users WHERE active = true;"
            let modifiedScript = "CREATE OR REPLACE VIEW active_users AS SELECT * FROM users WHERE deleted_at IS NULL;"
            let originalChecksum = checksum(sqlScript: originalScript)

            let resolver = MockResolver(
                migrationsResult: .success([
                    ResolvedMigration(
                        id: .repeatable(description: "refresh_views"),
                        description: "migrations/repeat.refresh_views.sql",
                        sqlScript: { modifiedScript }
                    )
                ])
            )
            let target = MockTarget(
                historyResult: .success([
                    SchemaHistoryRow(
                        id: .repeatable(description: "refresh_views"),
                        rank: 1,
                        description: "migrations/repeat.refresh_views.sql",
                        checksum: originalChecksum,
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ])
            )

            let migrator = Crane.Migrator(resolver: resolver, target: target)

            // Should not throw - repeatable migrations are allowed to change
            try await migrator.apply()
        }

        @Test func `Throws validation error when apply migration is missing`() async throws {
            let resolver = MockResolver(
                migrationsResult: .success([])
            )
            let target = MockTarget(
                historyResult: .success([
                    SchemaHistoryRow(
                        id: .apply(version: 1, description: "create_users"),
                        rank: 1,
                        description: "migrations/v1.create_users.apply.sql",
                        checksum: checksum(sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"),
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ])
            )

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
            let resolver = MockResolver(
                migrationsResult: .success([])
            )
            let target = MockTarget(
                historyResult: .success([
                    SchemaHistoryRow(
                        id: .undo(version: 1, description: "create_users"),
                        rank: 1,
                        description: "migrations/v1.create_users.undo.sql",
                        checksum: checksum(sqlScript: "DROP TABLE users;"),
                        user: "slashmo",
                        executionDate: .now,
                        duration: .milliseconds(42),
                        succeeded: true
                    )
                ])
            )

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
    }
}

private struct MockResolver: MigrationResolver {
    let migrationsResult: Result<[ResolvedMigration], any Error>

    func migrations() async throws -> [ResolvedMigration] {
        try migrationsResult.get()
    }
}

private struct MockTarget: MigrationTarget {
    let historyResult: Result<[SchemaHistoryRow], any Error>

    func history() async throws -> [SchemaHistoryRow] {
        try historyResult.get()
    }
}
