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

import Crypto
import Foundation

/// Computes a SHA-256 checksum of an SQL script.
///
/// This function generates a deterministic checksum for SQL migration scripts by:
/// - Removing the Unicode BOM (Byte Order Mark) if present
/// - Normalizing line endings (handles `\r\n`, `\r`, and `\n`)
/// - Trimming trailing whitespace from each line
/// - Using consistent `\n` line separators in the hash computation
///
/// The normalization ensures that the same logical SQL content produces identical checksums
/// regardless of platform-specific line endings or trailing whitespace variations.
///
/// - Parameter sqlScript: The SQL script content to checksum.
/// - Returns: A lowercase hexadecimal string representation of the SHA-256 hash.
package func checksum(sqlScript: String) -> String {
    var sha = SHA256()
    var sqlScript = sqlScript[...]
    var currentLine = ""

    if sqlScript.hasPrefix(String.bom) {
        sqlScript.removeFirst()
    }

    while !sqlScript.isEmpty {
        let next = sqlScript.removeFirst()
        switch next {
        case "\r\n", "\r", "\n":
            // Reached end of current line => trim trailing whitespace and move onto next line
            currentLine.trimSuffix(while: \.isWhitespace)
            sha.update(data: Data(currentLine.utf8))

            if !sqlScript.isEmpty {
                // Add newline except after final line
                sha.update(data: Data.newLine)
                currentLine = ""
            }
        default:
            currentLine.append(next)
        }
    }

    return sha.finalize().map { String(format: "%02x", $0) }.joined()
}

extension String {
    fileprivate static let bom = "\u{FEFF}"
}

extension Data {
    fileprivate static let newLine = Data("\n".utf8)
}

extension String {
    mutating func trimSuffix(while predicate: (Character) throws -> Bool) rethrows {
        while let last, try predicate(last) {
            removeLast()
        }
    }
}
