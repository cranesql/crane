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
    private let pathStrings: [String]

    package init(
        paths: [String],
        rootPath: @autoclosure () -> String = FileManager.default.currentDirectoryPath
    ) throws {
        let rootPath = rootPath()
        let rootURL = URL(fileURLWithPath: rootPath)
        self.rootURL = rootURL
        guard !paths.isEmpty else {
            throw FileSystemMigrationResolverError.noPaths
        }
        self.pathStrings = paths
        self.urls = paths.map { rootURL.appendingPathComponent($0) }
    }

    package func migrations() async throws -> [ResolvedMigration] {
        var seen = [MigrationID: String]()
        var migrations = [ResolvedMigration]()

        for (pathString, url) in zip(pathStrings, urls) {
            // Apple Foundation's `enumerator(atPath:)` returns nil for missing/non-directory paths, but
            // swift-corelibs-foundation returns a non-nil enumerator that yields nothing — so we need an
            // explicit existence check for portable error reporting.
            var isDirectory = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory else {
                throw FileSystemMigrationResolverError.unreadablePath(url.path)
            }

            guard let enumerator = FileManager.default.enumerator(atPath: url.path) else {
                throw FileSystemMigrationResolverError.unreadablePath(url.path)
            }

            while let relativePath = enumerator.nextObject() as? String {
                // `fileAttributes` reads from the stat the enumerator already performed.
                let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory

                // Skip hidden files and directories. For hidden directories, also short-circuit descent —
                // important on Kubernetes ConfigMap mounts where a hidden timestamped sibling directory
                // holds the actual files (without the skip we'd walk every file in the sibling tree only
                // to discard them, and the duplicate-ID check below would trip on each one).
                //
                // See also: https://github.com/flyway/flyway/issues/1807
                if relativePath.hasPrefix(".") || relativePath.contains("/.") {
                    if isDirectory {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                // The enumerator yields directories alongside files; we only want files.
                if isDirectory { continue }

                let fileURL = url.appendingPathComponent(relativePath)
                guard fileURL.pathExtension == "sql" else { continue }

                let id = try MigrationID(parsingFileName: fileURL.lastPathComponent)
                let script = "\(pathString)/\(relativePath)"

                if let existing = seen[id] {
                    throw FileSystemMigrationResolverError.duplicateMigrationID(id, scripts: [existing, script])
                }
                seen[id] = script

                migrations.append(
                    ResolvedMigration(id: id, script: script) {
                        try String(contentsOf: fileURL, encoding: .utf8)
                    }
                )
            }
        }

        return migrations.sorted(by: { $0.id < $1.id })
    }
}

enum FileSystemMigrationResolverError: Error, Equatable {
    case noPaths
    case unreadablePath(String)
    case duplicateMigrationID(MigrationID, scripts: [String])
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
