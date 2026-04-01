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

import Foundation

func withTemporaryDirectories<T>(
    _ paths: String...,
    operation: (_ rootURL: URL, _ urls: [URL]) async throws -> T
) async throws -> T {
    let id = UUID().uuidString
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let urls = paths.map { rootURL.appendingPathComponent($0) }

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
