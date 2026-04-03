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

public struct Migrator<Target: MigrationTarget>: Sendable {
    private let resolver: any MigrationResolver
    private let target: Target
    private let measure: @Sendable (_ work: @Sendable () async throws -> Void) async throws -> Duration
    private let now: @Sendable () -> Date

    public init(
        rootPath: String = FileManager.default.currentDirectoryPath,
        paths: [String] = ["migrations"],
        target: Target
    ) throws {
        let resolver = try FileSystemMigrationResolver(paths: paths, rootPath: rootPath)
        self.init(resolver: resolver, target: target)
    }

    package init(
        resolver: some MigrationResolver,
        target: Target,
        measure: @escaping @Sendable (_ work: @Sendable () async throws -> Void) async throws -> Duration = {
            try await ContinuousClock().measure($0)
        },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.resolver = resolver
        self.target = target
        self.measure = measure
        self.now = now
    }

    public func apply() async throws {
        try await target.setUpHistory()
        let resolvedMigrations = try await resolver.migrations()
        let history = try await target.history()
        let state = try await validatedMigrationState(resolved: resolvedMigrations, history: history)
        let user = try await target.currentUser()
        var nextRank = history.count + 1

        for migration in resolvedMigrations {
            switch migration.id {
            case .apply(let version, _):
                let key = VersionedHistoryKey(version: version, type: .apply)
                if !state.appliedVersionedKeys.contains(key) {
                    let sqlScript = try await migration.sqlScript
                    try await executeMigration(
                        id: migration.id,
                        description: migration.description,
                        sqlScript: sqlScript,
                        rank: nextRank,
                        user: user
                    )
                    nextRank += 1
                }
            case .undo:
                continue
            case .repeatable:
                let sqlScript = try await migration.sqlScript
                let scriptChecksum = checksum(sqlScript: sqlScript)
                let shouldExecute: Bool
                if let lastChecksum = state.lastRepeatableChecksums[migration.description] {
                    shouldExecute = scriptChecksum != lastChecksum
                } else {
                    shouldExecute = true
                }
                if shouldExecute {
                    try await executeMigration(
                        id: migration.id,
                        description: migration.description,
                        sqlScript: sqlScript,
                        rank: nextRank,
                        user: user
                    )
                    nextRank += 1
                }
            }
        }
    }

    private func executeMigration(
        id: MigrationID,
        description: String,
        sqlScript: String,
        rank: Int,
        user: String
    ) async throws {
        let scriptChecksum = checksum(sqlScript: sqlScript)
        try await target.withTransaction {
            let duration = try await measure {
                try await target.execute(sqlScript)
            }
            let row = SchemaHistoryRow(
                id: id,
                rank: rank,
                description: description,
                checksum: scriptChecksum,
                user: user,
                executionDate: now(),
                duration: duration,
                succeeded: true
            )
            try await target.record(row)
        }
    }

    /// Errors that can occur during migration validation.
    package enum ValidationError: Error, Equatable {
        /// A migration file has been modified after being applied to the database.
        case checksumMismatch(id: MigrationID, description: String, expected: String, actual: String)

        /// A previously executed migration is no longer resolved by the migration resolver.
        case missingMigration(version: Int, type: SchemaHistoryRow.MigrationType, description: String)

        /// A schema history row contained a versioned migration type without a version.
        case missingVersion(type: SchemaHistoryRow.MigrationType, description: String)

        /// A schema history row for a repeatable migration had a version set.
        case repeatableMigrationWithVersion(version: Int, description: String)
    }

    private func validatedMigrationState(
        resolved: [ResolvedMigration],
        history: [SchemaHistoryRow]
    ) async throws -> ValidatedMigrationState {
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

        var appliedVersionedKeys = Set<VersionedHistoryKey>()
        var lastRepeatableChecksums = [String: String]()

        for row in history {
            switch row.type {
            case .apply, .undo:
                guard let version = row.version else {
                    throw ValidationError.missingVersion(type: row.type, description: row.description)
                }

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

                appliedVersionedKeys.insert(key)

            case .repeatable:
                if let version = row.version {
                    throw ValidationError.repeatableMigrationWithVersion(
                        version: version, description: row.description
                    )
                }

                lastRepeatableChecksums[row.description] = row.checksum
            }
        }

        return ValidatedMigrationState(
            appliedVersionedKeys: appliedVersionedKeys,
            lastRepeatableChecksums: lastRepeatableChecksums
        )
    }
}

private struct VersionedHistoryKey: Hashable {
    let version: Int
    let type: SchemaHistoryRow.MigrationType
}

private struct ValidatedMigrationState {
    let appliedVersionedKeys: Set<VersionedHistoryKey>
    let lastRepeatableChecksums: [String: String]
}
