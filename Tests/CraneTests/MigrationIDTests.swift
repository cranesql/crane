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
struct `Migration ID` {
    @Suite
    struct `Sorting` {
        @Test func `Apply before same-version undo`() {
            #expect(
                MigrationID.apply(version: 1, description: "create_users")
                    < .undo(version: 1, description: "create_users")
            )
        }

        @Test func `Apply before higher-version apply`() {
            #expect(
                MigrationID.apply(version: 1, description: "create_users")
                    < .apply(version: 2, description: "create_todos")
            )
        }

        @Test func `Undo before higher-version apply`() {
            #expect(
                .undo(version: 1, description: "create_users")
                    < MigrationID.apply(version: 2, description: "create_todos")
            )
        }

        @Test func `Undo before higher-version undo`() {
            #expect(
                .undo(version: 1, description: "create_users")
                    < MigrationID.undo(version: 2, description: "create_todos")
            )
        }

        @Test func `Apply before repeatable`() {
            #expect(
                .apply(version: 1, description: "create_users") < MigrationID.repeatable(description: "refresh_views")
            )
        }

        @Test func `Undo before repeatable`() {
            #expect(
                .undo(version: 1, description: "create_users") < MigrationID.repeatable(description: "refresh_views")
            )
        }

        @Test func `Repeatable not before apply`() {
            #expect(
                (MigrationID.repeatable(description: "refresh_views") < .apply(version: 1, description: "create_users"))
                    == false
            )
        }

        @Test func `Repeatable not before undo`() {
            #expect(
                (MigrationID.repeatable(description: "refresh_views") < .undo(version: 1, description: "create_users"))
                    == false
            )
        }

        @Test func `Repeatable alphabetic`() {
            #expect(MigrationID.repeatable(description: "a") < .repeatable(description: "b"))
        }
    }
}
