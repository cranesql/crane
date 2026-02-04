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
struct `Migration ID file name parsing` {
    @Suite struct `Apply` {
        @Test func `With defaults`() throws {
            let fileName = "v1.create_users.apply.sql"

            let id = try MigrationID(parsingFileName: fileName)

            try #expect(id == .apply(version: 1, description: "create_users"))
        }

        @Test func `With empty version prefix`() throws {
            let fileName = "1.create_users.apply.sql"

            let id = try MigrationID(parsingFileName: fileName, versionPrefix: "")

            try #expect(id == .apply(version: 1, description: "create_users"))
        }

        @Test func `Without version prefix`() throws {
            let fileName = "1.create_users.apply.sql"

            let id = try MigrationID(parsingFileName: fileName, versionPrefix: nil)

            try #expect(id == .apply(version: 1, description: "create_users"))
        }

        @Test func `With custom identifier`() throws {
            let fileName = "v1.create_users.up.sql"

            let id = try MigrationID(parsingFileName: fileName, applyIdentifier: "up")

            try #expect(id == .apply(version: 1, description: "create_users"))
        }

        @Test func `Throws error with mismatching version prefix`() throws {
            let fileName = "1.create_users.apply.sql"

            let error = FileSystemMigrationIDParsingError.invalidVersionPrefix(
                malformedFileName: fileName,
                expectedPrefix: "v"
            )

            #expect(throws: error) {
                try MigrationID(parsingFileName: fileName)
            }
        }

        @Test func `Throws error with non-integer version`() throws {
            let fileName = "vone.create_users.apply.sql"

            let error = FileSystemMigrationIDParsingError.nonIntegerVersion("one")

            #expect(throws: error) {
                try MigrationID(parsingFileName: fileName)
            }
        }
    }

    @Suite struct `Undo` {
        @Test func `With defaults`() throws {
            let fileName = "v1.create_users.undo.sql"

            let id = try MigrationID(parsingFileName: fileName)

            try #expect(id == .undo(version: 1, description: "create_users"))
        }

        @Test func `With empty version prefix`() throws {
            let fileName = "1.create_users.undo.sql"

            let id = try MigrationID(parsingFileName: fileName, versionPrefix: "")

            try #expect(id == .undo(version: 1, description: "create_users"))
        }

        @Test func `Without version prefix`() throws {
            let fileName = "1.create_users.undo.sql"

            let id = try MigrationID(parsingFileName: fileName, versionPrefix: nil)

            try #expect(id == .undo(version: 1, description: "create_users"))
        }

        @Test func `With custom identifier`() throws {
            let fileName = "v1.create_users.down.sql"

            let id = try MigrationID(parsingFileName: fileName, undoIdentifier: "down")

            try #expect(id == .undo(version: 1, description: "create_users"))
        }

        @Test func `Throws error with mismatching version prefix`() throws {
            let fileName = "1.create_users.undo.sql"

            let error = FileSystemMigrationIDParsingError.invalidVersionPrefix(
                malformedFileName: fileName,
                expectedPrefix: "v"
            )

            #expect(throws: error) {
                try MigrationID(parsingFileName: fileName)
            }
        }

        @Test func `Throws error with non-integer version`() throws {
            let fileName = "vone.create_users.undo.sql"

            let error = FileSystemMigrationIDParsingError.nonIntegerVersion("one")

            #expect(throws: error) {
                try MigrationID(parsingFileName: fileName)
            }
        }
    }

    @Test func `Throws error without direction identifier`() {
        let fileName = "v1.create_users.sql"

        let error = FileSystemMigrationIDParsingError.invalidDirectionIdentifier(
            malformedFileName: fileName,
            expectedDirectionIdentifiers: ["apply", "undo"]
        )

        #expect(throws: error) {
            try MigrationID(parsingFileName: fileName)
        }
    }

    @Test func `Throws error if description contains description suffix`() {
        let fileName = "v1.this.is.the.description.apply.sql"

        let error = FileSystemMigrationIDParsingError.invalidDirectionIdentifier(
            malformedFileName: fileName,
            expectedDirectionIdentifiers: ["apply", "undo"]
        )

        #expect(throws: error) {
            try MigrationID(parsingFileName: fileName)
        }
    }

    @Test func `Throws error on empty file name`() {
        #expect(throws: (any Error).self) {
            try MigrationID(parsingFileName: "")
        }
    }

    @Suite struct `Repeatable` {
        @Test func `With defaults`() throws {
            let fileName = "repeat.refresh_views.sql"

            let id = try MigrationID(parsingFileName: fileName)

            #expect(id == .repeatable(description: "refresh_views"))
        }

        @Test func `With custom identifier`() throws {
            let fileName = "r.refresh_views.sql"

            let id = try MigrationID(parsingFileName: fileName, repeatIdentifier: "r")

            #expect(id == .repeatable(description: "refresh_views"))
        }
    }

    @Suite struct `Description` {
        @Test(arguments: [
            ("v1.create_users.apply.sql", MigrationID.apply(version: 1, description: "create_users")),
            ("v1.create_users.undo.sql", MigrationID.undo(version: 1, description: "create_users")),
            ("repeat.refresh_views.sql", MigrationID.repeatable(description: "refresh_views")),
        ])
        func `With defaults`(fileName: String, expectedID: MigrationID) throws {
            #expect(try MigrationID(parsingFileName: fileName) == expectedID)
        }

        @Test(arguments: [
            ("v1-create_users.apply.sql", MigrationID.apply(version: 1, description: "create_users")),
            ("v1-create_users.undo.sql", MigrationID.undo(version: 1, description: "create_users")),
            ("repeat-refresh_views.sql", MigrationID.repeatable(description: "refresh_views")),
        ])
        func `With custom prefix`(fileName: String, expectedID: MigrationID) throws {
            let id = try MigrationID(parsingFileName: fileName, descriptionPrefix: "-")

            #expect(id == expectedID)
        }

        @Test(arguments: [
            ("v1.create_users-apply.sql", MigrationID.apply(version: 1, description: "create_users")),
            ("v1.create_users-undo.sql", MigrationID.undo(version: 1, description: "create_users")),
            ("repeat.refresh_views.sql", MigrationID.repeatable(description: "refresh_views")),
        ])
        func `With custom suffix`(fileName: String, expectedID: MigrationID) throws {
            let id = try MigrationID(parsingFileName: fileName, descriptionSuffix: "-")

            #expect(id == expectedID)
        }

        @Test
        func `Throws error without description prefix`() throws {
            let fileName = "v1"

            let error = FileSystemMigrationIDParsingError.invalidDescriptionPrefix(
                malformedFileName: fileName,
                expectedPrefix: "."
            )

            #expect(throws: error) {
                try MigrationID(parsingFileName: fileName)
            }
        }

        @Test
        func `Throws error without description suffix`() throws {
            let fileName = "v1.never_ending_description"

            let error = FileSystemMigrationIDParsingError.invalidDescriptionSuffix(
                malformedFileName: fileName,
                expectedSuffix: "."
            )

            #expect(throws: error) {
                try MigrationID(parsingFileName: fileName)
            }
        }
    }
}
