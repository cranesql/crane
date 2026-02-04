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
import Foundation
import Testing

@Suite struct `Schema History Row` {
    @Test func `Maps apply migration`() {
        let id = MigrationID.apply(version: 42, description: "create_users")
        let checksum = checksum(sqlScript: "SELECT VERSION();")
        let executionDate = Date(timeIntervalSince1970: 42)

        let expectedRow = SchemaHistoryRow(
            rank: 1,
            version: 42,
            description: "create_users",
            relativeFilePath: "migrations/v42.create_users.apply.sql",
            type: .apply,
            checksum: checksum,
            user: "slashmo",
            executionDate: executionDate,
            duration: .milliseconds(42),
            succeeded: true
        )

        let row = SchemaHistoryRow(
            id: id,
            rank: 1,
            relativeFilePath: "migrations/v42.create_users.apply.sql",
            checksum: checksum,
            user: "slashmo",
            executionDate: executionDate,
            duration: .milliseconds(42),
            succeeded: true
        )

        #expect(row == expectedRow)
    }

    @Test func `Maps undo migration`() {
        let id = MigrationID.undo(version: 42, description: "create_users")
        let checksum = checksum(sqlScript: "DROP TABLE users;")
        let executionDate = Date(timeIntervalSince1970: 100)

        let expectedRow = SchemaHistoryRow(
            rank: 2,
            version: 42,
            description: "create_users",
            relativeFilePath: "migrations/v42.create_users.undo.sql",
            type: .undo,
            checksum: checksum,
            user: "slashmo",
            executionDate: executionDate,
            duration: .milliseconds(25),
            succeeded: true
        )

        let row = SchemaHistoryRow(
            id: id,
            rank: 2,
            relativeFilePath: "migrations/v42.create_users.undo.sql",
            checksum: checksum,
            user: "slashmo",
            executionDate: executionDate,
            duration: .milliseconds(25),
            succeeded: true
        )

        #expect(row == expectedRow)
    }

    @Test func `Maps repeatable migration`() {
        let id = MigrationID.repeatable(description: "refresh_views")
        let checksum = checksum(
            sqlScript: "CREATE OR REPLACE VIEW active_users AS SELECT * FROM users WHERE active = true;"
        )
        let executionDate = Date(timeIntervalSince1970: 200)

        let expectedRow = SchemaHistoryRow(
            rank: 3,
            version: nil,
            description: "refresh_views",
            relativeFilePath: "migrations/repeat.refresh_views.sql",
            type: .repeatable,
            checksum: checksum,
            user: "slashmo",
            executionDate: executionDate,
            duration: .milliseconds(15),
            succeeded: true
        )

        let row = SchemaHistoryRow(
            id: id,
            rank: 3,
            relativeFilePath: "migrations/repeat.refresh_views.sql",
            checksum: checksum,
            user: "slashmo",
            executionDate: executionDate,
            duration: .milliseconds(15),
            succeeded: true
        )

        #expect(row == expectedRow)
    }
}
