public protocol MigrationTarget {
    func schemaHistoryExists(configuration: SchemaHistoryTableConfiguration) async throws -> Bool
    func createSchemaHistory(configuration: SchemaHistoryTableConfiguration) async throws
}
