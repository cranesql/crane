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

enum MigrationID: Hashable, Comparable {
    case apply(version: Int, description: String)
    case undo(version: Int, description: String)
    case repeatable(description: String)

    static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.apply(lhsVersion, _), .apply(rhsVersion, _)):
            lhsVersion < rhsVersion
        case let (.apply(lhsVersion, _), .undo(rhsVersion, _)):
            lhsVersion <= rhsVersion
        case let (.undo(lhsVersion, _), .apply(rhsVersion, _)):
            lhsVersion < rhsVersion
        case let (.undo(lhsVersion, _), .undo(rhsVersion, _)):
            lhsVersion < rhsVersion
        case (.apply, .repeatable), (.undo, .repeatable):
            true
        case (.repeatable, .apply), (.repeatable, .undo):
            false
        case let (.repeatable(lhsDescription), .repeatable(rhsDescription)):
            lhsDescription < rhsDescription
        }
    }
}
