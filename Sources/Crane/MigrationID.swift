enum MigrationID: Hashable {
    case apply(version: String, description: String)
    case undo(version: String, description: String)
    case repeatable(description: String)
}
