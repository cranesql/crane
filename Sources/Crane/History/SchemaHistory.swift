import Foundation

struct SchemaHistory<Target: MigrationTarget> {
    private let target: Target

    init(target: Target) {
        self.target = target
    }

    func appliedMigrations() async throws -> [AppliedMigration] {
        try await target.appliedMigrations()
    }

    func recordAppliedMigration(
        id: MigrationID,
        rank: Int,
        relativeFilePath: String?,
        script: String,
        user: String,
        appliedAt: Date,
        duration: Duration,
        succeeded: Bool
    ) async throws {
        let appliedMigration = AppliedMigration(
            id: id,
            rank: rank,
            relativeFilePath: relativeFilePath,
            checksum: Checksum.hash(script: script),
            user: user,
            appliedAt: appliedAt,
            duration: duration,
            succeeded: succeeded
        )

        try await target.appendAppliedMigration(appliedMigration)
    }
}

/// Represents a row in the schema history table, tracking applied migrations.
public struct AppliedMigration: Hashable, Sendable {
    /// Order in which this migration was applied.
    public let rank: Int

    /// Version number for versioned migrations, nil for repeatable migrations.
    public let version: Int?

    /// Human-readable description from the migration filename.
    public let description: String

    /// Type of migration.
    public let type: MigrationType

    /// Script filename or path.
    public let relativeFilePath: String?

    /// Checksum for detecting changes to the migration file.
    public let checksum: String

    /// Database user who executed the migration.
    public let user: String

    /// Timestamp when the migration was applied.
    public let appliedAt: Date

    /// Execution duration.
    public let duration: Duration

    /// Whether the migration executed successfully.
    public let succeeded: Bool

    public init(
        rank: Int,
        version: Int?,
        description: String,
        type: MigrationType,
        relativeFilePath: String,
        checksum: String,
        user: String,
        appliedAt: Date,
        duration: Duration,
        succeeded: Bool
    ) {
        self.rank = rank
        self.version = version
        self.description = description
        self.type = type
        self.relativeFilePath = relativeFilePath
        self.checksum = checksum
        self.user = user
        self.appliedAt = appliedAt
        self.duration = duration
        self.succeeded = succeeded
    }

    package init(
        id: MigrationID,
        rank: Int,
        relativeFilePath: String?,
        checksum: String,
        user: String,
        appliedAt: Date,
        duration: Duration,
        succeeded: Bool
    ) {
        switch id {
        case let .apply(version, description):
            self.version = version
            self.description = description
            self.type = .apply
        case let .undo(version, description):
            self.version = version
            self.description = description
            self.type = .undo
        case let .repeatable(description):
            self.version = nil
            self.description = description
            self.type = .repeatable
        }
        self.rank = rank
        self.relativeFilePath = relativeFilePath
        self.checksum = checksum
        self.user = user
        self.appliedAt = appliedAt
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
