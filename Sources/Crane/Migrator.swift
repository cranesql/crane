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

public struct Migrator<Target: MigrationTarget> {
    private let resolver: any MigrationResolver
    private let target: Target

    package init(resolver: some MigrationResolver, target: Target) {
        self.resolver = resolver
        self.target = target
    }

    public func apply() async throws {
        let resolvedMigrations = try await resolver.migrations()
        let history = try await target.history()
        try await validateExecutedMigrations(resolved: resolvedMigrations, history: history)
    }

    /// Errors that can occur during migration validation.
    package enum ValidationError: Error, Equatable {
        /// A migration file has been modified after being applied to the database.
        case checksumMismatch(id: MigrationID, description: String, expected: String, actual: String)

        /// A previously executed migration is no longer resolved by the migration resolver.
        case missingMigration(version: Int, type: SchemaHistoryRow.MigrationType, description: String)
    }

    private func validateExecutedMigrations(resolved: [ResolvedMigration], history: [SchemaHistoryRow]) async throws {
        var resolvedByVersionAndType: [VersionedHistoryKey: ResolvedMigration] = [:]
        for migration in resolved {
            switch migration.id {
            case .apply(let version, _):
                resolvedByVersionAndType[VersionedHistoryKey(version: version, type: .apply)] = migration
            case .undo(let version, _):
                resolvedByVersionAndType[VersionedHistoryKey(version: version, type: .undo)] = migration
            case .repeatable:
                continue
            }
        }

        for row in history where row.version != nil {
            let version = row.version!
            let key = VersionedHistoryKey(version: version, type: row.type)
            guard let resolvedMigration = resolvedByVersionAndType[key] else {
                throw ValidationError.missingMigration(
                    version: version,
                    type: row.type,
                    description: row.description
                )
            }

            let sqlScript = try await resolvedMigration.sqlScript
            let currentChecksum = checksum(sqlScript: sqlScript)

            if currentChecksum != row.checksum {
                throw ValidationError.checksumMismatch(
                    id: resolvedMigration.id,
                    description: row.description,
                    expected: row.checksum,
                    actual: currentChecksum
                )
            }
        }
    }
}

private struct VersionedHistoryKey: Hashable {
    let version: Int
    let type: SchemaHistoryRow.MigrationType
}
