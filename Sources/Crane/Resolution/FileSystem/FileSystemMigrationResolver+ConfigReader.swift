//===----------------------------------------------------------------------===//
//
// This source file is part of the Crane open source project
//
// Copyright (c) 2026 the Crane project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if Configuration
package import Configuration

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension FileSystemMigrationResolver {
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    package init(reader: ConfigReader) throws {
        let rootPath = reader.string(
            forKey: "rootPath",
            default: FileManager.default.currentDirectoryPath
        )
        let paths = reader.stringArray(
            forKey: "paths",
            default: ["migrations"]
        )
        try self.init(paths: paths, rootPath: rootPath)
    }
}
#endif
