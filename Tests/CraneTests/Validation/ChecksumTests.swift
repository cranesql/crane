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

import Crane
import Testing

@Suite struct Checksum {
    @Test func `Creates stable checksum`() {
        let sqlScript = """
            CREATE TABLE users (
                id UUID PRIMARY KEY,
                name TEXT NOT NULL
            );

            """
        let expectedChecksum = "f71998f4ca388b4d231711ea6fb1537c8fb6bf49aea6da59f4019a29921d186f"

        let checksum = checksum(sqlScript: sqlScript)

        #expect(checksum == expectedChecksum)
    }

    @Test func `Normalizes line endings and whitespace`() {
        let expectedChecksum = "8b2fd1ca9ca0e73cfe018cf8ffcb661e88f75da1d2353214d50def02b8b343c2"

        // All of these should produce the same checksum
        let withoutLineEnding = "CREATE TABLE users (id UUID PRIMARY KEY);"
        let unixLineEndings = "CREATE TABLE users (id UUID PRIMARY KEY);\n"
        let windowsLineEndings = "CREATE TABLE users (id UUID PRIMARY KEY);\r\n"
        let classicMacLineEndings = "CREATE TABLE users (id UUID PRIMARY KEY);\r"
        let trailingWhitespace = "CREATE TABLE users (id UUID PRIMARY KEY);  \n"
        let withBOM = "\u{FEFF}CREATE TABLE users (id UUID PRIMARY KEY);\n"
        let allCombined = "\u{FEFF}CREATE TABLE users (id UUID PRIMARY KEY);  \r\n"

        #expect(checksum(sqlScript: withoutLineEnding) == expectedChecksum)
        #expect(checksum(sqlScript: unixLineEndings) == expectedChecksum)
        #expect(checksum(sqlScript: windowsLineEndings) == expectedChecksum)
        #expect(checksum(sqlScript: classicMacLineEndings) == expectedChecksum)
        #expect(checksum(sqlScript: trailingWhitespace) == expectedChecksum)
        #expect(checksum(sqlScript: withBOM) == expectedChecksum)
        #expect(checksum(sqlScript: allCombined) == expectedChecksum)
    }

    @Test func `Preserves empty lines`() {
        let sqlScript = """
            CREATE TABLE users (id UUID PRIMARY KEY);

            CREATE TABLE todos (id UUID PRIMARY KEY);

            """

        let withEmptyLines = checksum(sqlScript: sqlScript)

        let withoutEmptyLines = """
            CREATE TABLE users (id UUID PRIMARY KEY);
            CREATE TABLE todos (id UUID PRIMARY KEY);

            """

        #expect(checksum(sqlScript: withoutEmptyLines) != withEmptyLines, "Empty lines should be preserved")
    }

    @Test func `Preserves indentation`() {
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

        #expect(
            checksum(sqlScript: withIndentation) != checksum(sqlScript: withoutIndentation),
            "Indentation should be preserverd."
        )
    }

    @Test func `Handles empty script`() {
        #expect(checksum(sqlScript: "") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func `Handles complex SQL with comments`() {
        let sqlScript = """
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
        let expectedChecksum = "0787161ad40e3430415d05e024dbc6db67874a87ac0d2d09ddda8dff84ccdd49"

        #expect(checksum(sqlScript: sqlScript) == expectedChecksum)

        let windowsVersion = sqlScript.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(checksum(sqlScript: windowsVersion) == expectedChecksum)
    }
}
