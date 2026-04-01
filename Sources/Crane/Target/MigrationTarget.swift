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

/// A target database that executes and keeps track of migrations.
public protocol MigrationTarget {
    /// Retrieves the complete migration history from the target system.
    ///
    /// This method queries the schema history table to return all previously
    /// executed migrations, ordered by their execution rank.
    ///
    /// - Returns: An array of schema history rows representing all executed migrations.
    /// - Throws: An error if the history cannot be retrieved from the target.
    func history() async throws -> [SchemaHistoryRow]

    /// Execute the given SQL migration script.
    ///
    /// - Parameter sqlScript: The raw SQL script to execute.
    /// - Throws: An error if the target couldn't execute the SQL script.
    func execute(_ sqlScript: String) async throws
}
