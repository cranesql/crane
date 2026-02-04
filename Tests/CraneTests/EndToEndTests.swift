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
import Foundation
import Logging
import Synchronization
import Testing

@Suite struct `End-to-End` {
    private let logger: Logger

    init() {
        var logger = Logger(label: "End-to-end")
        logger.logLevel = .trace
        self.logger = logger
    }

    @Test func `Applies pending migrations`() async throws {
        try await withTemporaryDirectories("migrations") { rootURL, urls in
            // Create migration files
            try "CREATE TABLE users (id INT);".write(
                to: urls[0].appendingPathComponent("v001.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "CREATE TABLE posts (id INT, user_id INT);".write(
                to: urls[0].appendingPathComponent("v002.create_posts.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;".write(
                to: urls[0].appendingPathComponent("repeat.refresh_views.sql"),
                atomically: true,
                encoding: .utf8
            )
            
            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path())
            let target = MockMigrationTarget()
            let migrator = Crane.Migrator(
                resolver: resolver,
                target: target,
                logger: logger,
                currentDate: { Date(timeIntervalSince1970: 42) },
                measure: { operation in
                    try await operation()
                    return .milliseconds(42)
                }
            )

            try await migrator.apply()

            #expect(
                target.executedMigrationScripts == [
                    "CREATE TABLE users (id INT);",
                    "CREATE TABLE posts (id INT, user_id INT);",
                    "CREATE OR REPLACE VIEW user_stats AS SELECT COUNT(*) FROM users;",
                ]
            )

            #expect(
                target.appliedMigrations == [
                    AppliedMigration(
                        rank: 1,
                        version: 1,
                        description: "create_users",
                        type: .apply,
                        relativeFilePath: "migrations/v001.create_users.apply.sql",
                        checksum: "5ea918fac5561634f4b577815b41483e5882b9c57dd3bd2351e3422d641af545",
                        user: "testuser",
                        appliedAt: Date(timeIntervalSince1970: 42),
                        duration: .milliseconds(42),
                        succeeded: true
                    ),
                    AppliedMigration(
                        rank: 2,
                        version: 2,
                        description: "create_posts",
                        type: .apply,
                        relativeFilePath: "migrations/v002.create_posts.apply.sql",
                        checksum: "19988b87b9e1407713b60aa720857c62bd66ae8abc89c220b083ca06d6cc1f85",
                        user: "testuser",
                        appliedAt: Date(timeIntervalSince1970: 42),
                        duration: .milliseconds(42),
                        succeeded: true
                    ),
                    AppliedMigration(
                        rank: 3,
                        version: nil,
                        description: "refresh_views",
                        type: .repeatable,
                        relativeFilePath: "migrations/repeat.refresh_views.sql",
                        checksum: "2df1bffc01172dcb7f711602870c81f2ac0f1c8b7f5179b0c11165e23cd8c0b3",
                        user: "testuser",
                        appliedAt: Date(timeIntervalSince1970: 42),
                        duration: .milliseconds(42),
                        succeeded: true
                    ),
                ]
            )
        }
    }

    @Test func `Initializes with default parameters`() async throws {
        let target = MockMigrationTarget()
        _ = try Crane.Migrator(target: target)
    }
}

// MARK: - Test Helpers

private final class MockMigrationTarget: MigrationTarget {
    var executedMigrationScripts: [String] {
        _executedMigrationScripts.withLock(\.self)
    }

    var appliedMigrations: [AppliedMigration] {
        _appliedMigrations.withLock(\.self)
    }

    private let _previouslyAppliedMigrations: [AppliedMigration]
    private let _executedMigrationScripts = Mutex([String]())
    private let _appliedMigrations = Mutex([AppliedMigration]())

    init(previouslyAppliedMigrations: [AppliedMigration] = []) {
        self._previouslyAppliedMigrations = previouslyAppliedMigrations
    }

    func currentUser() async throws -> String {
        "testuser"
    }

    func appliedMigrations() async throws -> [AppliedMigration] {
        _previouslyAppliedMigrations
    }

    func executeMigrationScript(_ script: String) async throws {
        _executedMigrationScripts.withLock {
            $0.append(script)
        }
    }

    func appendAppliedMigration(_ migration: AppliedMigration) async throws {
        _appliedMigrations.withLock {
            $0.append(migration)
        }
    }
}
