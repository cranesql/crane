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

struct ResolvedMigration: Identifiable {
    let id: MigrationID
    private let _sqlScript: @Sendable () async throws -> String

    var sqlScript: String {
        get async throws {
            try await _sqlScript()
        }
    }

    init(id: MigrationID, sqlScript: @escaping @Sendable () async throws -> String) {
        self.id = id
        self._sqlScript = sqlScript
    }
}
