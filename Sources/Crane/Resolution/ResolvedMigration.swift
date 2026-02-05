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

/// A migration that has been resolved by a ``MigrationResolver``.
///
/// This type represents a migration that has been discovered and can be executed.
/// It contains the migration's identity, a description, and provides access to the SQL script.
package struct ResolvedMigration: Identifiable {
    /// The unique identifier for this migration.
    package let id: MigrationID

    /// A description of the migration source.
    ///
    /// The content of this field depends on the resolver that created the migration:
    /// - For file-system resolvers: Contains the relative file path (e.g., "migrations/v1.create_users.apply.sql")
    /// - For other resolvers: May contain resolver-specific identifying information
    package let description: String

    private let _sqlScript: @Sendable () async throws -> String

    /// The SQL script content for this migration.
    ///
    /// Accessing this property may perform I/O operations (e.g., reading from disk).
    package var sqlScript: String {
        get async throws {
            try await _sqlScript()
        }
    }

    /// Creates a new resolved migration.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for the migration.
    ///   - description: A description of the migration source. For file-system resolvers, this should be the relative file path.
    ///   - sqlScript: A closure that provides the SQL script content when called. This allows for lazy loading of the script.
    package init(id: MigrationID, description: String, sqlScript: @escaping @Sendable () async throws -> String) {
        self.id = id
        self.description = description
        self._sqlScript = sqlScript
    }
}
