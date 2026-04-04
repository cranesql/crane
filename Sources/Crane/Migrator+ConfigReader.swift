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
public import Configuration

extension Migrator {
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public init(reader: ConfigReader, target: Target) throws {
        try self.init(
            resolver: FileSystemMigrationResolver(reader: reader.scoped(to: "crane")),
            target: target
        )
    }
}
#endif
