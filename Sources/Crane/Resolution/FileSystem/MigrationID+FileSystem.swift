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

extension MigrationID {
    init(
        parsingFileName fileName: String,
        versionPrefix: String? = "v",
        repeatIdentifier: String = "repeat",
        descriptionPrefix: String = ".",
        descriptionSuffix: String = ".",
        applyIdentifier: String = "apply",
        undoIdentifier: String = "undo"
    ) throws {
        let versionPrefix = versionPrefix?[...].utf8
        let repeatIdentifier = repeatIdentifier[...].utf8
        let descriptionPrefix = descriptionPrefix[...].utf8
        let descriptionSuffix = descriptionSuffix[...].utf8
        let applyIdentifier = applyIdentifier[...].utf8
        let undoIdentifier = undoIdentifier[...].utf8
        let originalFileName = fileName
        var fileName = fileName[...].utf8
        var state = ParsingState.parsingVersionPrefix

        func popDescriptionPrefix() throws {
            guard fileName.starts(with: descriptionPrefix) else {
                throw FileSystemMigrationIDParsingError.invalidDescriptionPrefix(
                    malformedFileName: originalFileName,
                    expectedPrefix: String(decoding: descriptionPrefix, as: UTF8.self)
                )
            }
            fileName.removeFirst(descriptionPrefix.count)
        }

        func popDescriptionSuffix() throws {
            guard fileName.starts(with: descriptionSuffix) else {
                throw FileSystemMigrationIDParsingError.invalidDescriptionSuffix(
                    malformedFileName: originalFileName,
                    expectedSuffix: String(decoding: descriptionSuffix, as: UTF8.self)
                )
            }
            fileName.removeFirst(descriptionSuffix.count)
        }

        while !fileName.isEmpty {
            switch state {
            case .parsingVersionPrefix:
                if let versionPrefix, fileName.starts(with: versionPrefix) {
                    fileName.removeFirst(versionPrefix.count)
                    state = .parsingVersion
                } else if fileName.starts(with: repeatIdentifier) {
                    fileName.removeFirst(repeatIdentifier.count)
                    try popDescriptionPrefix()
                    state = .parsingDescription(version: nil)
                } else if versionPrefix == nil {
                    state = .parsingVersion
                } else {
                    throw FileSystemMigrationIDParsingError.invalidVersionPrefix(
                        malformedFileName: originalFileName,
                        expectedPrefix: versionPrefix.flatMap(String.init)
                    )
                }
            case .parsingVersion:
                let versionLowerBound = fileName.startIndex
                var versionUpperBound = versionLowerBound
                while versionUpperBound < fileName.endIndex,
                    !fileName[versionUpperBound...].starts(with: descriptionPrefix)
                {
                    fileName.formIndex(after: &versionUpperBound)
                }
                let version = fileName[versionLowerBound..<versionUpperBound]
                fileName.removeFirst(version.count)
                try popDescriptionPrefix()
                state = .parsingDescription(version: version)
            case .parsingDescription(let version):
                let descriptionLowerBound = fileName.startIndex
                var descriptionUpperBound = descriptionLowerBound

                if let version {
                    while descriptionUpperBound < fileName.endIndex,
                        !fileName[descriptionUpperBound...].starts(with: descriptionSuffix)
                    {
                        fileName.formIndex(after: &descriptionUpperBound)
                    }
                    let description = fileName[descriptionLowerBound..<descriptionUpperBound]
                    fileName.removeFirst(description.count)
                    try popDescriptionSuffix()
                    state = .parsingDirection(version: version, description: description)
                } else {
                    // repeatable migration file names end after description, so look for "." to indicate file ending
                    while descriptionUpperBound < fileName.endIndex,
                        !fileName[descriptionUpperBound...].starts(with: "."[...].utf8)
                    {
                        fileName.formIndex(after: &descriptionUpperBound)
                    }
                    let description = fileName[descriptionLowerBound..<descriptionUpperBound]
                    fileName.removeFirst(description.count)
                    state = .parsingFileEnding(directionalVersion: nil, description: description)
                }
            case let .parsingDirection(version, description):
                if fileName.starts(with: applyIdentifier) {
                    fileName.removeFirst(applyIdentifier.count)
                    state = .parsingFileEnding(directionalVersion: (.apply, version), description: description)
                } else if fileName.starts(with: undoIdentifier) {
                    fileName.removeFirst(undoIdentifier.count)
                    state = .parsingFileEnding(directionalVersion: (.undo, version), description: description)
                } else {
                    throw FileSystemMigrationIDParsingError.invalidDirectionIdentifier(
                        malformedFileName: originalFileName,
                        expectedDirectionIdentifiers: [
                            String(decoding: applyIdentifier, as: UTF8.self),
                            String(decoding: undoIdentifier, as: UTF8.self),
                        ]
                    )
                }
            case let .parsingFileEnding(directionalVersion, description):
                let description = String(decoding: description, as: UTF8.self)

                if let (direction, version) = directionalVersion {
                    let version = String(decoding: version, as: UTF8.self)
                    switch direction {
                    case .apply:
                        self = .apply(version: version, description: description)
                    case .undo:
                        self = .undo(version: version, description: description)
                    }
                } else {
                    self = .repeatable(description: description)
                }
                return
            }
        }

        throw FileSystemMigrationIDParsingError.malformedFileName(originalFileName)
    }

    private enum ParsingState {
        case parsingVersionPrefix
        case parsingVersion
        case parsingDescription(version: Substring.UTF8View?)
        case parsingDirection(version: Substring.UTF8View, description: Substring.UTF8View)
        case parsingFileEnding(directionalVersion: (Direction, Substring.UTF8View)?, description: Substring.UTF8View)

        enum Direction {
            case apply, undo
        }
    }
}

enum FileSystemMigrationIDParsingError: Error, Equatable {
    case invalidVersionPrefix(malformedFileName: String, expectedPrefix: String?)
    case invalidDescriptionPrefix(malformedFileName: String, expectedPrefix: String)
    case invalidDescriptionSuffix(malformedFileName: String, expectedSuffix: String)
    case invalidDirectionIdentifier(malformedFileName: String, expectedDirectionIdentifiers: [String])
    case malformedFileName(String)
}
