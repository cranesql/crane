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
                to: urls[0].appending(path: "v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "DROP TABLE users;".write(
                to: urls[0].appending(path: "v1.create_users.undo.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "SELECT VERSION();".write(
                to: urls[0].appending(path: "repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.migrations()

            try #require(
                migrations.map(\.id) == [
                    .apply(version: 1, description: "create_users"),
                    .undo(version: 1, description: "create_users"),
                    .repeatable(description: "version"),
                ]
            )

            #expect(try await migrations[0].sqlScript == "CREATE TABLE users (id UUID PRIMARY KEY);")
            #expect(try await migrations[1].sqlScript == "DROP TABLE users;")
            #expect(try await migrations[2].sqlScript == "SELECT VERSION();")
        }
    }

    @Test func `Ignores migration files from nested paths if not configured`() async throws {
        try await withTemporaryDirectories("migrations") { rootURL, urls in
            let nestedFolderURL = rootURL.appending(path: "migrations/repeatable")
            try FileManager.default.createDirectory(at: nestedFolderURL, withIntermediateDirectories: false)
            try "SELECT VERSION();".write(
                to: nestedFolderURL.appending(path: "repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appending(path: "v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "DROP TABLE users;".write(
                to: urls[0].appending(path: "v1.create_users.undo.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(paths: ["migrations"], rootPath: rootURL.path)

            let migrations = try await resolver.migrations()

            #expect(
                migrations.map(\.id) == [
                    .apply(version: 1, description: "create_users"),
                    .undo(version: 1, description: "create_users"),
                ]
            )
        }
    }

    @Test func `Resolves migration files from nested paths if configured`() async throws {
        try await withTemporaryDirectories("migrations", "migrations/repeatable") { rootURL, urls in
            try "CREATE TABLE users (id UUID PRIMARY KEY);".write(
                to: urls[0].appending(path: "v1.create_users.apply.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "DROP TABLE users;".write(
                to: urls[0].appending(path: "v1.create_users.undo.sql"),
                atomically: true,
                encoding: .utf8
            )
            try "SELECT VERSION();".write(
                to: urls[1].appending(path: "repeat.version.sql"),
                atomically: true,
                encoding: .utf8
            )

            let resolver = try FileSystemMigrationResolver(
                paths: ["migrations", "migrations/repeatable"],
                rootPath: rootURL.path
            )

            let migrations = try await resolver.migrations()

            #expect(
                migrations.map(\.id) == [
                    .apply(version: 1, description: "create_users"),
                    .undo(version: 1, description: "create_users"),
                    .repeatable(description: "version"),
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

private func withTemporaryDirectories<T>(
    _ paths: String...,
    operation: (_ rootURL: URL, _ urls: [URL]) async throws -> T
) async throws -> T {
    let id = UUID().uuidString
    let rootURL = URL.temporaryDirectory.appending(path: id)
    let urls = paths.map { rootURL.appending(path: $0) }

    do {
        for url in urls {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let result = try await operation(rootURL, urls)
        try FileManager.default.removeItem(at: rootURL)
        return result
    } catch {
        try? FileManager.default.removeItem(at: rootURL)
        throw error
    }
}
