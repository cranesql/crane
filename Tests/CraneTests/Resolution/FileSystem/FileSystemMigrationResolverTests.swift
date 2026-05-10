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

#if Configuration
import Configuration
#endif

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

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path + "/")

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        script: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        script: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        script: "migrations/repeat.version.sql",
                        sqlScript: "SELECT VERSION();"
                    ),
                ]
            )
        }
    }

    @Test func `Resolves migration files recursively from nested directories`() async throws {
        try await withTemporaryDirectories("migrations", "migrations/nested") { rootURL, urls in
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

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        script: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        script: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        script: "migrations/nested/repeat.version.sql",
                        sqlScript: "SELECT VERSION();"
                    ),
                ]
            )
        }
    }

    @Test func `Composes migrations from multiple independent roots`() async throws {
        try await withTemporaryDirectories("a", "b") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "SELECT VERSION();".write(
                to: urls[1].appendingPathComponent("repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["a", "b"], rootPath: rootURL.path)

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        script: "a/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        script: "b/repeat.version.sql",
                        sqlScript: "SELECT VERSION();"
                    ),
                ]
            )
        }
    }

    @Test func `Fails to initialize without paths`() async throws {
        #expect(throws: (any Error).self) {
            try FileSystemMigrationResolver(paths: [])
        }
    }

    @Test func `Throws when a configured path does not exist`() async throws {
        try await withTemporaryDirectories("a") { rootURL, _ in
            let resolver = try FileSystemMigrationResolver(paths: ["b"], rootPath: rootURL.path)
            let expectedPath = rootURL.appendingPathComponent("b").path

            await #expect(throws: FileSystemMigrationResolverError.unreadablePath(expectedPath)) {
                _ = try await resolver.migrations()
            }
        }
    }

    @Test func `Skips hidden directories`() async throws {
        // Without this, Foundation's enumerator descends into the hidden timestamped sibling Kubernetes
        // maintains for ConfigMap mounts, surfacing each SQL file twice.
        try await withTemporaryDirectories("migrations", "migrations/..hidden") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "SELECT VERSION();".write(
                to: urls[1].appendingPathComponent("repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        script: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    )
                ]
            )
        }
    }

    @Test func `Skips non-SQL files`() async throws {
        try await withTemporaryDirectories("migrations") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "# Migrations".write(
                to: urls[0].appendingPathComponent("README.md"),
                atomically: true,
                encoding: .utf8
            )
            try "binary".write(
                to: urls[0].appendingPathComponent(".DS_Store"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        script: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    )
                ]
            )
        }
    }

    @Test func `Throws when the same migration ID is resolved from multiple paths`() async throws {
        try await withTemporaryDirectories("a", "b") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[1].appendingPathComponent("v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["a", "b"], rootPath: rootURL.path)

            await #expect(
                throws: FileSystemMigrationResolverError.duplicateMigrationID(
                    .apply(version: 1, description: "create_users"),
                    scripts: [
                        "a/v1.create_users.apply.sql",
                        "b/v1.create_users.apply.sql",
                    ]
                )
            ) {
                _ = try await resolver.migrations()
            }
        }
    }

    #if Configuration
    @Suite struct `Configuration` {
        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
        @Test func `Reads rootPath and paths from config reader`() async throws {
            try await withTemporaryDirectories("sql") { rootURL, urls in
                try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                    to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                    atomically: true,
                    encoding: .utf8
                )

                let reader = ConfigReader(
                    provider: InMemoryProvider(values: [
                        "rootPath": ConfigValue(.string(rootURL.path), isSecret: false),
                        "paths": ConfigValue(.stringArray(["sql"]), isSecret: false),
                    ])
                )
                let resolver = try FileSystemMigrationResolver(reader: reader)

                let migrations = try await resolver.migrations()

                #expect(
                    try await migrations.equatable == [
                        EquatableResolvedMigration(
                            id: .apply(version: 1, description: "create_users"),
                            script: "sql/v1.create_users.apply.sql",
                            sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                        )
                    ]
                )
            }
        }

        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
        @Test func `Defaults to migrations path`() async throws {
            try await withTemporaryDirectories("migrations") { rootURL, urls in
                try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                    to: urls[0].appendingPathComponent("v1.create_users.apply.sql"),
                    atomically: true,
                    encoding: .utf8
                )

                let reader = ConfigReader(
                    provider: InMemoryProvider(values: [
                        "rootPath": ConfigValue(.string(rootURL.path), isSecret: false)
                    ])
                )
                let resolver = try FileSystemMigrationResolver(reader: reader)

                let migrations = try await resolver.migrations()

                #expect(
                    try await migrations.equatable == [
                        EquatableResolvedMigration(
                            id: .apply(version: 1, description: "create_users"),
                            script: "migrations/v1.create_users.apply.sql",
                            sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                        )
                    ]
                )
            }
        }
    }
    #endif
}

extension [ResolvedMigration] {
    fileprivate var equatable: [EquatableResolvedMigration] {
        get async throws {
            var result = [EquatableResolvedMigration]()
            for migration in self {
                result.append(try await EquatableResolvedMigration(migration))
            }
            return result
        }
    }
}

private struct EquatableResolvedMigration: Equatable {
    let id: MigrationID
    let script: String
    let sqlScript: String

    init(id: MigrationID, script: String, sqlScript: String) {
        self.id = id
        self.script = script
        self.sqlScript = sqlScript
    }

    init(_ resolvedMigration: ResolvedMigration) async throws {
        self.id = resolvedMigration.id
        self.script = resolvedMigration.script
        self.sqlScript = try await resolvedMigration.sqlScript
    }
}
