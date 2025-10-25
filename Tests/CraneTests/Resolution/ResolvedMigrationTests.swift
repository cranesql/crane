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
struct `Resolved Migration` {
    @Suite
    struct `SQL Script` {
        @Test func `Provides access to SQL script`() async throws {
            let sqlScript = "CREATE TABLE users (id UUID PRIMARY KEY);\n"

            let migration = ResolvedMigration(
                id: .apply(version: 1, description: "create_users"),
                sqlScript: { sqlScript }
            )

            #expect(try await migration.sqlScript == sqlScript)
        }

        @Test func `Throws error when failing to access SQL script`() async {
            struct TestError: Error {}

            let migration = ResolvedMigration(
                id: .apply(version: 1, description: "create_users"),
                sqlScript: { throw TestError() }
            )

            await #expect(throws: TestError.self) {
                try await migration.sqlScript
            }
        }
    }
}
