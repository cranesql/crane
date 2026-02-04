import Foundation
import Logging

public struct Migrator<Target: MigrationTarget>: Sendable {
    private let resolver: any MigrationResolver
    private let target: Target
    private let schemaHistory: SchemaHistory<Target>
    private let logger: Logger
    private let currentDate: @Sendable () -> Date
    private let measure: @Sendable (_ operation: () async throws -> Void) async throws -> Duration

    public init(
        target: Target,
        migrationFilePaths: [String] = ["migrations"],
        rootPath: String = FileManager.default.currentDirectoryPath
    ) throws {
        let resolver = try FileSystemMigrationResolver(paths: migrationFilePaths, rootPath: rootPath)
        let clock = ContinuousClock()
        self.init(
            resolver: resolver,
            target: target,
            logger: Logger(label: "Migrator"),
            currentDate: { .now },
            measure: { operation in
                try await clock.measure { try await operation() }
            }
        )
    }

    package init(
        resolver: any MigrationResolver,
        target: Target,
        logger: Logger,
        currentDate: @escaping @Sendable () -> Date,
        measure: @escaping @Sendable (_ operation: () async throws -> Void) async throws -> Duration
    ) {
        self.resolver = resolver
        self.target = target
        self.schemaHistory = SchemaHistory(target: target)
        self.currentDate = currentDate
        self.measure = measure

        var logger = logger
        logger[metadataKey: "target"] = "\(type(of: target))"
        self.logger = logger
    }

    public func apply() async throws {
        let user = try await target.currentUser()
        var logger = logger
        logger[metadataKey: "user"] = "\(user)"

        let resolvedMigrations = try await resolver.migrations()
        logger.debug("Resolved migrations.")
        let appliedMigrations = try await schemaHistory.appliedMigrations()
        logger.debug("Fetched applied migrations.")

        // Validate that applied migrations haven't been modified
        try await validateAppliedMigrations(resolved: resolvedMigrations, applied: appliedMigrations)
        logger.debug("Validated applied migrations.")

        let pendingMigrations = try await pendingMigrations(resolved: resolvedMigrations, applied: appliedMigrations)
        logger.debug("Calculated pending migrations.")

        for (index, migration) in pendingMigrations.enumerated() {
            let rank = appliedMigrations.count + index + 1
            let script = migration.sqlScript
            let duration = try await measure {
                try await target.executeMigrationScript(script)
            }
            try await schemaHistory.recordAppliedMigration(
                id: migration.id,
                rank: rank,
                relativeFilePath: migration.relativeFilePath,
                script: migration.sqlScript,
                user: user,
                appliedAt: currentDate(),
                duration: duration,
                succeeded: true
            )
        }
    }

    /// Validates that applied versioned migrations have not been modified.
    ///
    /// - Parameters:
    ///   - resolved: All migrations discovered from the filesystem.
    ///   - applied: Migrations that have already been executed and recorded in the schema history.
    /// - Throws: `ValidationError.checksumMismatch` if an applied migration has been modified.
    private func validateAppliedMigrations(
        resolved: [ResolvedMigration],
        applied: [AppliedMigration]
    ) async throws {
        // Build a lookup for resolved migrations by version
        var resolvedByVersion: [Int: ResolvedMigration] = [:]
        for migration in resolved {
            if case .apply(let version, _) = migration.id {
                resolvedByVersion[version] = migration
            }
        }

        // Validate checksums for all applied versioned migrations
        for appliedMigration in applied where appliedMigration.type == .apply {
            guard let version = appliedMigration.version else { continue }
            guard let resolvedMigration = resolvedByVersion[version] else { continue }

            let script = try await resolvedMigration.sqlScript
            let currentChecksum = Checksum.hash(script: script)

            if currentChecksum != appliedMigration.checksum {
                throw ValidationError.checksumMismatch(
                    version: version,
                    description: appliedMigration.description,
                    expected: appliedMigration.checksum,
                    actual: currentChecksum
                )
            }
        }
    }

    /// Computes which migrations need to be executed based on resolved and applied migrations.
    ///
    /// - Parameters:
    ///   - resolved: All migrations discovered from the filesystem.
    ///   - applied: Migrations that have already been executed and recorded in the schema history.
    /// - Returns: An array of pending migrations (versioned first, then repeatable) that need to be executed.
    func pendingMigrations(
        resolved: [ResolvedMigration],
        applied: [AppliedMigration]
    ) async throws -> [PendingMigration] {

        // Track the latest state for each version
        let versionStates = buildVersionStates(applied: applied)

        // Build a lookup for the latest applied repeatable migration by description
        var latestRepeatableChecksums: [String: String] = [:]
        for appliedMigration in applied where appliedMigration.type == .repeatable {
            latestRepeatableChecksums[appliedMigration.description] = appliedMigration.checksum
        }

        // Filter resolved migrations to find pending migrations
        var pendingVersioned: [PendingMigration] = []
        var pendingRepeatable: [PendingMigration] = []

        for migration in resolved {
            switch migration.id {
            case .apply(let version, _):
                // Apply migration is pending if:
                // - Never applied before, OR
                // - Most recent operation was an undo
                let latestState = versionStates[version]
                if latestState == nil || latestState == .undo {
                    let script = try await migration.sqlScript
                    pendingVersioned.append(
                        PendingMigration(
                            id: migration.id,
                            relativeFilePath: migration.relativeFilePath,
                            sqlScript: script
                        )
                    )
                }
            case .repeatable(let description):
                let script = try await migration.sqlScript
                let currentChecksum = Checksum.hash(script: script)

                // Repeatable migration is pending if:
                // - Never applied before, OR
                // - Checksum has changed
                if let lastChecksum = latestRepeatableChecksums[description] {
                    if currentChecksum != lastChecksum {
                        pendingRepeatable.append(
                            PendingMigration(
                                id: migration.id,
                                relativeFilePath: migration.relativeFilePath,
                                sqlScript: script
                            )
                        )
                    }
                } else {
                    pendingRepeatable.append(
                        PendingMigration(
                            id: migration.id,
                            relativeFilePath: migration.relativeFilePath,
                            sqlScript: script
                        )
                    )
                }
            case .undo:
                break
            }
        }

        // Sort versioned migrations by migration ID (already Comparable)
        let sortedVersioned = pendingVersioned.sorted { $0.id < $1.id }

        // Sort repeatable migrations alphabetically by description
        let sortedRepeatable = pendingRepeatable.sorted { $0.id < $1.id }

        // Return versioned migrations first, then repeatable migrations
        return sortedVersioned + sortedRepeatable
    }

    /// Builds a lookup of the latest state (apply/undo) for each migration version.
    ///
    /// - Parameter applied: Migrations that have already been executed.
    /// - Returns: A dictionary mapping version numbers to their latest migration type.
    private func buildVersionStates(applied: [AppliedMigration]) -> [Int: AppliedMigration.MigrationType] {
        // Sort applied migrations by rank to process them in chronological order
        let sortedApplied = applied.sorted { $0.rank < $1.rank }

        var versionStates: [Int: AppliedMigration.MigrationType] = [:]

        for appliedMigration in sortedApplied {
            if let version = appliedMigration.version,
                appliedMigration.type == .apply || appliedMigration.type == .undo
            {
                versionStates[version] = appliedMigration.type
            }
        }

        return versionStates
    }

    /// Errors that can occur during migration validation.
    enum ValidationError: Error {
        /// A migration file has been modified after being applied to the database.
        case checksumMismatch(version: Int, description: String, expected: String, actual: String)
    }
}

/// Represents a migration that needs to be executed.
struct PendingMigration: Identifiable, Hashable {
    /// The migration identifier.
    let id: MigrationID

    /// The relative file path in case the migration was resolved from the file system.
    let relativeFilePath: String?

    /// The SQL script content.
    let sqlScript: String
}
