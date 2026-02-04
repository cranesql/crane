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

@Suite
struct ChecksumTests {
    @Test func `Creates stable checksum`() {
        let script = """
            CREATE TABLE users (
                id UUID PRIMARY KEY,
                name TEXT NOT NULL
            );

            """
        let expectedChecksum = "217070dc80b4bf0d93652c81209c0643152be62e12e774fa708c401bfc936064"

        let checksum = Checksum.hash(script: script)
        for _ in 0..<100 {
            #expect(checksum == expectedChecksum)
        }
    }

    @Test func `Normalizes line endings and whitespace`() {
        let expectedChecksum = "f39e253974858b40aa337266866554e10d0960b24ed17d301d51978cbc30f7dc"

        // All of these should produce the same checksum
        let unixLineEndings = "CREATE TABLE users (id UUID PRIMARY KEY);\n"
        let windowsLineEndings = "CREATE TABLE users (id UUID PRIMARY KEY);\r\n"
        let classicMacLineEndings = "CREATE TABLE users (id UUID PRIMARY KEY);\r"
        let trailingWhitespace = "CREATE TABLE users (id UUID PRIMARY KEY);  \n"
        let withBOM = "\u{FEFF}CREATE TABLE users (id UUID PRIMARY KEY);\n"
        let allCombined = "\u{FEFF}CREATE TABLE users (id UUID PRIMARY KEY);  \r\n"

        #expect(Checksum.hash(script: unixLineEndings) == expectedChecksum)
        #expect(Checksum.hash(script: windowsLineEndings) == expectedChecksum)
        #expect(Checksum.hash(script: classicMacLineEndings) == expectedChecksum)
        #expect(Checksum.hash(script: trailingWhitespace) == expectedChecksum)
        #expect(Checksum.hash(script: withBOM) == expectedChecksum)
        #expect(Checksum.hash(script: allCombined) == expectedChecksum)
    }

    @Test func `Preserves empty lines`() {
        let script = """
            CREATE TABLE users (id UUID PRIMARY KEY);

            CREATE TABLE todos (id UUID PRIMARY KEY);

            """

        let checksum = Checksum.hash(script: script)

        // Empty lines should be preserved in the checksum
        let withoutEmptyLines = """
            CREATE TABLE users (id UUID PRIMARY KEY);
            CREATE TABLE todos (id UUID PRIMARY KEY);

            """

        #expect(Checksum.hash(script: withoutEmptyLines) != checksum)
    }

    @Test func `Preserves leading whitespace`() {
        let withIndentation = """
            CREATE TABLE users (
                id UUID PRIMARY KEY,
                name TEXT NOT NULL
            );

            """

        let withoutIndentation = """
            CREATE TABLE users (
            id UUID PRIMARY KEY,
            name TEXT NOT NULL
            );

            """

        // Leading whitespace (indentation) should be preserved
        #expect(Checksum.hash(script: withIndentation) != Checksum.hash(script: withoutIndentation))
    }

    @Test func `Handles empty script`() {
        let emptyScript = ""
        let checksum = Checksum.hash(script: emptyScript)

        // Empty script should produce a consistent checksum
        #expect(checksum == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func `Handles complex SQL with comments`() {
        let script = """
            -- Create users table
            CREATE TABLE users (
                id UUID PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            /* Create indexes for performance */
            CREATE INDEX idx_users_email ON users(email);
            CREATE INDEX idx_users_created_at ON users(created_at);

            -- Grant permissions
            GRANT SELECT, INSERT ON users TO app_user;

            """
        let expectedChecksum = "83ca4cc643de15752c299563692e89865683931e39a9210756c28ed9e9802cfc"

        #expect(Checksum.hash(script: script) == expectedChecksum)

        let windowsVersion = script.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(Checksum.hash(script: windowsVersion) == expectedChecksum)
    }
}
