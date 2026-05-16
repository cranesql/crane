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
    private(set) var lockCount = 0
    private(set) var activeLockCount = 0
    private(set) var activeLockCountWhileSettingUpHistory = 0
    private(set) var activeLockCountWhileReadingHistory = 0
    private(set) var activeLockCountWhileReadingCurrentUser = 0
    private(set) var activeLockCountWhileExecutingScript = 0
    private(set) var activeLockCountWhileRecordingRow = 0
    private(set) var activeLockCountWhileOpeningTransaction = 0
    private let historyResult: Result<[SchemaHistoryRow], any Error>
    private let stubbedCurrentUser: String?

    init(history: [SchemaHistoryRow] = [], currentUser: String? = "mock_user") {
        self.historyResult = .success(history)
        self.stubbedCurrentUser = currentUser
    }

    func setUpHistory() async throws {
        setUpHistoryCallCount += 1
        activeLockCountWhileSettingUpHistory = activeLockCount
    }

    func currentUser() async throws -> String? {
        activeLockCountWhileReadingCurrentUser = activeLockCount
        return stubbedCurrentUser
    }

    func history() async throws -> [SchemaHistoryRow] {
        activeLockCountWhileReadingHistory = activeLockCount
        return try historyResult.get()
    }

    func execute(_ sql: String) async throws {
        executedSQLScripts.append(sql)
        activeLockCountWhileExecutingScript = activeLockCount
    }

    func record(_ row: SchemaHistoryRow) async throws {
        recordedRows.append(row)
        activeLockCountWhileRecordingRow = activeLockCount
    }

    func withTransaction(_ body: @Sendable () async throws -> Void) async throws {
        transactionCount += 1
        activeLockCountWhileOpeningTransaction = activeLockCount
        try await body()
    }

    func withLock(_ body: @Sendable () async throws -> Void) async throws {
        lockCount += 1
        activeLockCount += 1
        defer { activeLockCount -= 1 }
        try await body()
    }
}
