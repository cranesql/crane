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

import Foundation
import Logging
import Testing

@testable import Crane

@Suite struct Migrator {
    @Suite struct Apply {
        let logger: Logger

        init() {
            var logger = Logger(label: "Apply")
            logger.logLevel = .trace
            self.logger = logger
        }

        @Test func `Applies pending migrations`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([
                    ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                        "CREATE TABLE users (id INT);"
                    }
                ]),
                target: target,
                logger: logger,
                currentDate: { Date(timeIntervalSince1970: 42) },
                measure: { operation in
                    try await operation()
                    return .milliseconds(42)
                }
            )

            try await migrator.apply()
        }

        @Test func `Throws error when applied migration checksum mismatches`() async throws {
            let applied = [
                AppliedMigration(
                    rank: 1,
                    version: 1,
                    description: "create_users",
                    type: .apply,
                    relativeFilePath: "migrations/v1.create_users.apply.sql",
                    checksum: Checksum.hash(script: "CREATE TABLE users (id INT);"),  // Original checksum
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(100),
                    succeeded: true
                )
            ]

            let target = MockMigrationTarget(appliedMigrations: applied)
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([
                    ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                        "CREATE TABLE users (id INT, name VARCHAR(255));"  // Modified!
                    }
                ]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            await #expect(throws: Crane.Migrator<MockMigrationTarget>.ValidationError.self) {
                try await migrator.apply()
            }
        }
    }

    @Suite struct `Pending Migrations` {
        let logger: Logger

        init() {
            var logger = Logger(label: "Pending Migrations")
            logger.logLevel = .trace
            self.logger = logger
        }

        @Test func `Returns all migrations when none are applied`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                },
                ResolvedMigration(id: .apply(version: 2, description: "create_posts")) {
                    "CREATE TABLE posts (id INT);"
                },
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: [])

            #expect(
                pending == [
                    PendingMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE users (id INT);"
                    ),
                    PendingMigration(
                        id: .apply(version: 2, description: "create_posts"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE posts (id INT);"
                    ),
                ]
            )
        }

        @Test func `Returns no migrations when all are applied`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                }
            ]

            let applied = [
                AppliedMigration(
                    rank: 1,
                    version: 1,
                    description: "create_users",
                    type: .apply,
                    relativeFilePath: "v1.create_users.apply.sql",
                    checksum: Checksum.hash(script: "CREATE TABLE users (id INT);"),
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(100),
                    succeeded: true
                )
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: applied)

            #expect(pending.isEmpty)
        }

        @Test func `Returns only unapplied migrations`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                },
                ResolvedMigration(id: .apply(version: 2, description: "create_posts")) {
                    "CREATE TABLE posts (id INT);"
                },
                ResolvedMigration(id: .apply(version: 3, description: "create_comments")) {
                    "CREATE TABLE comments (id INT);"
                },
            ]

            let applied = [
                AppliedMigration(
                    rank: 1,
                    version: 1,
                    description: "create_users",
                    type: .apply,
                    relativeFilePath: "v1.create_users.apply.sql",
                    checksum: Checksum.hash(script: "CREATE TABLE users (id INT);"),
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(100),
                    succeeded: true
                )
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: applied)

            #expect(
                pending == [
                    PendingMigration(
                        id: .apply(version: 2, description: "create_posts"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE posts (id INT);"
                    ),
                    PendingMigration(
                        id: .apply(version: 3, description: "create_comments"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE comments (id INT);"
                    ),
                ]
            )
        }

        @Test func `Returns undone migration as pending`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                }
            ]

            let applied = [
                AppliedMigration(
                    rank: 1,
                    version: 1,
                    description: "create_users",
                    type: .apply,
                    relativeFilePath: "v1.create_users.apply.sql",
                    checksum: Checksum.hash(script: "CREATE TABLE users (id INT);"),
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(100),
                    succeeded: true
                ),
                AppliedMigration(
                    rank: 2,
                    version: 1,
                    description: "create_users",
                    type: .undo,
                    relativeFilePath: "v1.create_users.undo.sql",
                    checksum: Checksum.hash(script: "DROP TABLE users;"),
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(50),
                    succeeded: true
                ),
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: applied)

            #expect(
                pending == [
                    PendingMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE users (id INT);"
                    )
                ]
            )
        }

        @Test func `Ignores undo migrations and includes repeatable after versioned`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                },
                ResolvedMigration(id: .undo(version: 1, description: "create_users")) {
                    "DROP TABLE users;"
                },
                ResolvedMigration(id: .repeatable(description: "refresh_views")) {
                    "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;"
                },
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: [])

            #expect(
                pending == [
                    PendingMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE users (id INT);"
                    ),
                    PendingMigration(
                        id: .repeatable(description: "refresh_views"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;"
                    ),
                ]
            )
        }

        @Test func `Returns migrations sorted by version`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .apply(version: 3, description: "create_comments")) {
                    "CREATE TABLE comments (id INT);"
                },
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                },
                ResolvedMigration(id: .apply(version: 2, description: "create_posts")) {
                    "CREATE TABLE posts (id INT);"
                },
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: [])

            #expect(
                pending == [
                    PendingMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE users (id INT);"
                    ),
                    PendingMigration(
                        id: .apply(version: 2, description: "create_posts"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE posts (id INT);"
                    ),
                    PendingMigration(
                        id: .apply(version: 3, description: "create_comments"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE comments (id INT);"
                    ),
                ]
            )
        }

        @Test func `Returns repeatable migration when never applied`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .repeatable(description: "refresh_views")) {
                    "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;"
                }
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: [])

            #expect(
                pending == [
                    PendingMigration(
                        id: .repeatable(description: "refresh_views"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;"
                    )
                ]
            )
        }

        @Test func `Returns repeatable migration when checksum changed`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .repeatable(description: "refresh_views")) {
                    "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*), SUM(score) FROM users;"
                }
            ]

            let applied = [
                AppliedMigration(
                    rank: 1,
                    version: nil,
                    description: "refresh_views",
                    type: .repeatable,
                    relativeFilePath: "repeat.refresh_views.sql",
                    checksum: Checksum.hash(script: "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;"),
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(50),
                    succeeded: true
                )
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: applied)

            #expect(
                pending == [
                    PendingMigration(
                        id: .repeatable(description: "refresh_views"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*), SUM(score) FROM users;"
                    )
                ]
            )
        }

        @Test func `Does not return repeatable migration when checksum unchanged`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let script = "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;"
            let resolved = [
                ResolvedMigration(id: .repeatable(description: "refresh_views")) {
                    script
                }
            ]

            let applied = [
                AppliedMigration(
                    rank: 1,
                    version: nil,
                    description: "refresh_views",
                    type: .repeatable,
                    relativeFilePath: "repeat.refresh_views.sql",
                    checksum: Checksum.hash(script: script),
                    user: "testuser",
                    appliedAt: Date(),
                    duration: .milliseconds(50),
                    succeeded: true
                )
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: applied)

            #expect(pending.isEmpty)
        }

        @Test func `Returns repeatable migrations in alphabetical order after versioned`() async throws {
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: StaticMigrationResolver([]),
                target: target,
                logger: logger,
                currentDate: { .now },
                measure: { operation in try await operation(); return .zero }
            )

            let resolved = [
                ResolvedMigration(id: .repeatable(description: "z_last")) {
                    "SELECT 3;"
                },
                ResolvedMigration(id: .apply(version: 1, description: "create_users")) {
                    "CREATE TABLE users (id INT);"
                },
                ResolvedMigration(id: .repeatable(description: "a_first")) {
                    "SELECT 1;"
                },
                ResolvedMigration(id: .repeatable(description: "m_middle")) {
                    "SELECT 2;"
                },
            ]

            let pending = try await migrator.pendingMigrations(resolved: resolved, applied: [])

            #expect(
                pending == [
                    PendingMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: nil,
                        sqlScript: "CREATE TABLE users (id INT);"
                    ),
                    PendingMigration(id: .repeatable(description: "a_first"), relativeFilePath: nil, sqlScript: "SELECT 1;"),
                    PendingMigration(id: .repeatable(description: "m_middle"), relativeFilePath: nil, sqlScript: "SELECT 2;"),
                    PendingMigration(id: .repeatable(description: "z_last"), relativeFilePath: nil, sqlScript: "SELECT 3;"),
                ]
            )
        }
    }
}

// MARK: - Stubs

private struct StaticMigrationResolver: MigrationResolver {
    private let _migrations: [ResolvedMigration]

    init(_ migrations: [ResolvedMigration]) {
        self._migrations = migrations
    }

    func migrations() async throws -> [ResolvedMigration] {
        _migrations
    }
}

private struct MockMigrationTarget: MigrationTarget {
    private let _appliedMigrations: [AppliedMigration]

    init(appliedMigrations: [AppliedMigration] = []) {
        self._appliedMigrations = appliedMigrations
    }

    func currentUser() async throws -> String {
        "testuser"
    }

    func run() async throws {
        // No-op for tests
    }

    func appliedMigrations() async throws -> [AppliedMigration] {
        _appliedMigrations
    }

    func executeMigrationScript(_ script: String) async throws {}

    func appendAppliedMigration(_ migration: AppliedMigration) async throws {
        print(migration)
    }
}
