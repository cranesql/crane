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

import Benchmark
import Crane
import Foundation

func fileSystemMigrationResolverBenchmarks() {
    makeFileSystemMigrationResolverResolveBenchmark()
    makeFileSystemMigrationResolverResolveRecursivelyBenchmark()
    makeFileSystemMigrationResolverReadSQLScriptBenchmark()
}

@discardableResult
private func makeFileSystemMigrationResolverResolveBenchmark() -> Benchmark? {
    let baseURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let migrationsURL = baseURL.appending(path: "migrations")

    return Benchmark("FileSystemMigrationResolver: Resolve") { benchmark in
        for _ in benchmark.scaledIterations {
            let resolver = try FileSystemMigrationResolver(
                paths: ["migrations"],
                rootPath: baseURL.path
            )
            blackHole(try await resolver.migrations())
        }
    } setup: {
        try FileManager.default.createDirectory(at: migrationsURL, withIntermediateDirectories: true)

        let stubMigrationData = Data("SELECT VERSION();\n".utf8)
        for i in 0..<1000 {
            let url = migrationsURL.appending(path: "v\(i).example.apply.sql")
            try stubMigrationData.write(to: url)
        }
    } teardown: {
        try FileManager.default.removeItem(at: baseURL)
    }
}

@discardableResult
private func makeFileSystemMigrationResolverResolveRecursivelyBenchmark() -> Benchmark? {
    let baseURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let migrationsURL = baseURL.appending(path: "migrations")

    return Benchmark("FileSystemMigrationResolver: Resolve recursively") { benchmark in
        for _ in benchmark.scaledIterations {
            let resolver = try FileSystemMigrationResolver(
                paths: ["migrations"],
                rootPath: baseURL.path
            )
            blackHole(try await resolver.migrations())
        }
    } setup: {
        try FileManager.default.createDirectory(at: migrationsURL, withIntermediateDirectories: true)

        // 1000 files split across 10 nested subdirectories (100 each).
        let stubMigrationData = Data("SELECT VERSION();\n".utf8)
        var version = 0
        for subdirIndex in 0..<10 {
            let subdirURL = migrationsURL.appending(path: "subdir\(subdirIndex)")
            try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: false)
            for _ in 0..<100 {
                let url = subdirURL.appending(path: "v\(version).example.apply.sql")
                try stubMigrationData.write(to: url)
                version += 1
            }
        }
    } teardown: {
        try FileManager.default.removeItem(at: baseURL)
    }
}

@discardableResult
private func makeFileSystemMigrationResolverReadSQLScriptBenchmark() -> Benchmark? {
    let baseURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let migrationsURL = baseURL.appending(path: "migrations")

    return Benchmark(
        "FileSystemMigrationResolver: Read SQL Script",
        configuration: .init(scalingFactor: .kilo)
    ) { benchmark in
        let resolver = try FileSystemMigrationResolver(
            paths: ["migrations"],
            rootPath: baseURL.path
        )
        let migrations = try await resolver.migrations()
        let migration = migrations[0]
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(try await migration.sqlScript)
        }
    } setup: {
        try FileManager.default.createDirectory(at: migrationsURL, withIntermediateDirectories: true)

        let stubMigrationData = Data("SELECT VERSION();\n".utf8)
        let url = migrationsURL.appending(path: "v1.example.apply.sql")
        try stubMigrationData.write(to: url)
    } teardown: {
        try FileManager.default.removeItem(at: baseURL)
    }
}
