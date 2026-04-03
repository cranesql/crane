//===----------------------------------------------------------------------===//
//
// This source file is part of the Crane open source project
//
// Copyright (c) 2026 the Crane project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crane

actor MockTarget: MigrationTarget {
    private(set) var executedSQLScripts = [String]()
    private(set) var recordedRows = [SchemaHistoryRow]()
    private(set) var transactionCount = 0
    private(set) var setUpHistoryCallCount = 0
    private let historyResult: Result<[SchemaHistoryRow], any Error>

    init(history: [SchemaHistoryRow] = []) {
        self.historyResult = .success(history)
    }

    func setUpHistory() async throws {
        setUpHistoryCallCount += 1
    }

    func currentUser() async throws -> String { "mock_user" }

    func history() async throws -> [SchemaHistoryRow] {
        try historyResult.get()
    }

    func execute(_ sql: String) async throws {
        executedSQLScripts.append(sql)
    }

    func record(_ row: SchemaHistoryRow) async throws {
        recordedRows.append(row)
    }

    func withTransaction(_ body: @Sendable () async throws -> Void) async throws {
        transactionCount += 1
        try await body()
    }
}
