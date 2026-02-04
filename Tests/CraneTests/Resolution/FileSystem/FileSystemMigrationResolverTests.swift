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

import Testing

@testable import Crane

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct `File-System Migration Resolver` {
    @Test func `Resolves migration files from single path`() async throws {
        try await withTemporaryDirectories("migrations") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "DROP TABLE users;".write(
                to: urls[0].appendingPathComponent("v1.create_users.undo.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "SELECT VERSION();".write(
                to: urls[0].appendingPathComponent("repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.equatableMigrations()

            #expect(
                migrations == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        relativeFilePath: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        relativeFilePath: "migrations/repeat.version.sql",
                        sqlScript: "SELECT VERSION();"
                    ),
                ]
            )
        }
    }

    @Test func `Ignores migration files from nested paths if not configured`() async throws {
        try await withTemporaryDirectories("migrations") { rootURL, urls in
            let nestedFolderURL = rootURL.appendingPathComponent("migrations/repeatable")
            try FileManager.default.createDirectory(at: nestedFolderURL, withIntermediateDirectories: false)
            try "SELECT VERSION();".write(
                to: nestedFolderURL.appendingPathComponent("repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "DROP TABLE users;".write(
                to: urls[0].appendingPathComponent("v1.create_users.undo.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.equatableMigrations()

            #expect(
                migrations == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        relativeFilePath: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                ]
            )
        }
    }

    @Test func `Resolves migration files from nested paths if configured`() async throws {
        try await withTemporaryDirectories("migrations", "migrations/repeatable") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "DROP TABLE users;".write(
                to: urls[0].appendingPathComponent("v1.create_users.undo.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "SELECT VERSION();".write(
                to: urls[1].appendingPathComponent("repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(
                paths: ["migrations", "migrations/repeatable"],
                rootPath: rootURL.path
            )

            let migrations = try await resolver.equatableMigrations()

            #expect(
                migrations == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        relativeFilePath: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        relativeFilePath: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        relativeFilePath: "migrations/repeatable/repeat.version.sql",
                        sqlScript: "SELECT VERSION();"
                    ),
                ]
            )
        }
    }

    @Test func `Fails to initialize without paths`() async throws {
        #expect(throws: Error.self) {
            try FileSystemMigrationResolver(paths: [])
        }
    }
}

private extension FileSystemMigrationResolver {
    func equatableMigrations() async throws -> [EquatableResolvedMigration] {
        var migrations = [EquatableResolvedMigration]()
        for migration in try await self.migrations() {
            migrations.append(try await EquatableResolvedMigration(migration))
        }
        return migrations
    }
}

private struct EquatableResolvedMigration: Identifiable, Equatable {
    let id: MigrationID
    let relativeFilePath: String?
    let sqlScript: String

    init(id: MigrationID, relativeFilePath: String?, sqlScript: String) {
        self.id = id
        self.relativeFilePath = relativeFilePath
        self.sqlScript = sqlScript
    }

    init(_ resolvedMigration: ResolvedMigration) async throws {
        self.id = resolvedMigration.id
        self.relativeFilePath = resolvedMigration.relativeFilePath
        self.sqlScript = try await resolvedMigration.sqlScript
    }
}
