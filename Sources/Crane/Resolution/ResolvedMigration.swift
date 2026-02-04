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

package struct ResolvedMigration: Identifiable {
    package let id: MigrationID
    package let relativeFilePath: String?
    private let _sqlScript: @Sendable () async throws -> String

    package var sqlScript: String {
        get async throws {
            try await _sqlScript()
        }
    }

    package init(id: MigrationID, relativeFilePath: String?, sqlScript: @escaping @Sendable () async throws -> String) {
        self.id = id
        self.relativeFilePath = relativeFilePath
        self._sqlScript = sqlScript
    }
}
