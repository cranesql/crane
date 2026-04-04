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
                        description: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        description: "migrations/repeat.version.sql",
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

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.undo.sql",
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

            let migrations = try await resolver.migrations()

            #expect(
                try await migrations.equatable == [
                    EquatableResolvedMigration(
                        id: .apply(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.apply.sql",
                        sqlScript: "CREATE TABLE users (id UUID PRIMARY KEY);"
                    ),
                    EquatableResolvedMigration(
                        id: .undo(version: 1, description: "create_users"),
                        description: "migrations/v1.create_users.undo.sql",
                        sqlScript: "DROP TABLE users;"
                    ),
                    EquatableResolvedMigration(
                        id: .repeatable(description: "version"),
                        description: "migrations/repeatable/repeat.version.sql",
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
                            description: "sql/v1.create_users.apply.sql",
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
                            description: "migrations/v1.create_users.apply.sql",
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
    let description: String
    let sqlScript: String

    init(id: MigrationID, description: String, sqlScript: String) {
        self.id = id
        self.description = description
        self.sqlScript = sqlScript
    }

    init(_ resolvedMigration: ResolvedMigration) async throws {
        self.id = resolvedMigration.id
        self.description = resolvedMigration.description
        self.sqlScript = try await resolvedMigration.sqlScript
    }
}
