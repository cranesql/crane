public protocol MigrationTarget: Sendable {
    func currentUser() async throws -> String
    func appliedMigrations() async throws -> [AppliedMigration]
    func appendAppliedMigration(_ migration: AppliedMigration) async throws
    func executeMigrationScript(_ script: String) async throws
}
