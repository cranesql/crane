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

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Represents a row in the schema history table.
public struct SchemaHistoryRow: Hashable, Sendable {
    /// Order in which this migration was applied.
    public let rank: Int

    /// Version number for versioned migrations, nil for repeatable migrations.
    public let version: Int?

    /// Human-readable description of the migration, parsed from the migration's identifier
    /// (e.g. "create_users").
    public let description: String

    /// Type of migration.
    public let type: MigrationType

    /// Checksum for detecting changes to the migration script.
    public let checksum: String

    /// Database user who executed the migration.
    ///
    /// Set to `nil` in case the migration target doesn't have the concept of users (e.g. SQLite).
    public let user: String?

    /// Timestamp when the migration was applied.
    public let executionDate: Date

    /// Execution duration.
    public let duration: Duration

    /// Whether the migration executed successfully.
    public let succeeded: Bool

    /// Creates a new schema history row.
    ///
    /// - Parameters:
    ///   - rank: Order in which this migration was applied.
    ///   - version: Version number for versioned migrations, nil for repeatable migrations.
    ///   - description: Human-readable description parsed from the migration identifier.
    ///   - type: Type of migration operation.
    ///   - checksum: Checksum for detecting changes to the migration script.
    ///   - user: Database user who executed the migration.
    ///     Set this to `nil` in case your migration target doesn't have the concept of users (e.g. SQLite).
    ///   - executionDate: Timestamp when the migration was applied.
    ///   - duration: Execution duration of the migration.
    ///   - succeeded: Whether the migration executed successfully.
    public init(
        rank: Int,
        version: Int?,
        description: String,
        type: MigrationType,
        checksum: String,
        user: String?,
        executionDate: Date,
        duration: Duration,
        succeeded: Bool
    ) {
        self.rank = rank
        self.version = version
        self.description = description
        self.type = type
        self.checksum = checksum
        self.user = user
        self.executionDate = executionDate
        self.duration = duration
        self.succeeded = succeeded
    }

    package init(
        id: MigrationID,
        rank: Int,
        checksum: String,
        user: String?,
        executionDate: Date,
        duration: Duration,
        succeeded: Bool
    ) {
        switch id {
        case let .apply(version, _):
            self.version = version
            self.type = .apply
        case let .undo(version, _):
            self.version = version
            self.type = .undo
        case .repeatable:
            self.version = nil
            self.type = .repeatable
        }
        self.rank = rank
        self.description = id.description
        self.checksum = checksum
        self.user = user
        self.executionDate = executionDate
        self.duration = duration
        self.succeeded = succeeded
    }

    /// The type of migration operation.
    public enum MigrationType: String, Hashable, Sendable {
        /// Forward migration that applies changes.
        case apply = "APPLY"

        /// Reverse migration that undoes changes.
        case undo = "UNDO"

        /// Repeatable migration that can be re-executed.
        case repeatable = "REPEATABLE"
    }
}
