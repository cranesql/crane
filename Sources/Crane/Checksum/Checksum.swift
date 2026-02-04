import Crypto
import Foundation

enum Checksum {
    static func hash(script: String) -> String {
        var hash = SHA256()

        // Normalize line endings by replacing \r\n and \r with \n
        let normalizedScript = script
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines = normalizedScript.split(separator: "\n", omittingEmptySubsequences: false)

        // Remove BOM from first line if present
        if let firstLine = lines.first, firstLine.hasPrefix("\u{FEFF}") {
            lines[0] = firstLine.dropFirst()
        }

        for (index, line) in lines.enumerated() {
            // Trim trailing whitespace
            var processedLine = line
            while processedLine.last?.isWhitespace == true {
                processedLine = processedLine.dropLast()
            }

            // Update hash with line content
            hash.update(data: Data(processedLine.utf8))

            // Add newline after each line except the last
            if index < lines.count - 1 {
                hash.update(data: Data("\n".utf8))
            }
        }

        let digest = hash.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
