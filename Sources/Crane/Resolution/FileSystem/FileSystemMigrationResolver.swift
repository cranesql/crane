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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

package struct FileSystemMigrationResolver: MigrationResolver {
    private let rootURL: URL
    private let urls: [URL]

    package init(
        paths: [String],
        rootPath: @autoclosure () -> String = FileManager.default.currentDirectoryPath
    ) throws {
        let rootURL = URL(fileURLWithPath: rootPath())
        self.rootURL = rootURL
        guard !paths.isEmpty else {
            throw FileSystemMigrationResolverError.noPaths
        }
        self.urls = paths.map { rootURL.appendingPathComponent($0) }
    }

    package func migrations() async throws -> [ResolvedMigration] {
        let fileURLs = try urls.flatMap { url in
            try FileManager.default.contentsOfDirectory(atPath: url.path).map { url.appendingPathComponent($0) }
        }

        let migrations = try fileURLs.lazy
            .compactMap { url -> ResolvedMigration? in
                var isDirectory = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory else {
                    return nil
                }
                let id = try MigrationID(parsingFileName: url.lastPathComponent)
                return ResolvedMigration(id: id) {
                    try String(contentsOf: url, encoding: .utf8)
                }
            }
            .sorted(by: { $0.id < $1.id })

        return migrations
    }
}

enum FileSystemMigrationResolverError: Error {
    case noPaths
}

#if canImport(ObjectiveC)
extension FileManager {
    fileprivate func fileExists(atPath path: String, isDirectory: inout Bool) -> Bool {
        var legacyIsDirectory: ObjCBool = false
        let fileExists = fileExists(atPath: path, isDirectory: &legacyIsDirectory)
        isDirectory = legacyIsDirectory.boolValue
        return fileExists
    }
}
#endif
