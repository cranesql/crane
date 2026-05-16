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
public protocol MigrationTarget: Sendable {
    /// Set up the schema history table, creating it if it doesn't already exist.
    ///
    /// Called by the migrator before any other operations on the target.
    func setUpHistory() async throws

    /// Retrieve the username of the current database connection.
    ///
    /// Used to populate the `user` field of ``SchemaHistoryRow`` when recording migrations.
    ///
    /// - Note: Return `nil` in case your target doesn't have the concept of users (e.g. SQLite).
    ///   Don't return `nil` on failures, throw instead.
    func currentUser() async throws -> String?

    /// Retrieve the complete migration history from the target system.
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

    /// Record a migration execution in the schema history.
    ///
    /// - Parameter row: The schema history row to persist.
    /// - Throws: An error if the row cannot be recorded.
    func record(_ row: SchemaHistoryRow) async throws

    /// Execute the given closure within a transaction.
    ///
    /// If the closure throws, the transaction is rolled back.
    ///
    /// - Important: Targets where the database does not support transactional DDL may execute
    ///   statements outside of a real transaction, making this best-effort.
    ///
    /// - Parameter body: The work to perform within the transaction.
    /// - Throws: An error if the transaction fails or the body throws.
    func withTransaction(_ body: @Sendable () async throws -> Void) async throws

    /// Execute the given closure while holding an exclusive cross-process lock on the target.
    ///
    /// Used to serialize concurrent ``Migrator/apply()`` runs from multiple processes
    /// (e.g. multiple application replicas starting in parallel).
    ///
    /// - Important: Targets where the database does not support cross-process locks may execute
    ///   the body without one, making this best-effort.
    ///
    /// - Parameter body: The work to perform while holding the lock.
    /// - Throws: An error if the lock cannot be acquired or the body throws.
    func withLock(_ body: @Sendable () async throws -> Void) async throws
}
