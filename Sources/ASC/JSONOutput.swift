import Foundation

/// Shared helpers for emitting machine-readable JSON from commands.
///
/// Every command accepts a global `--json` flag. When set, the command prints
/// a single JSON document to stdout (and nothing else) so other clients can
/// parse the result programmatically.
enum JSONOutput {
    /// Encodes `value` as a pretty-printed, stable-key-ordered JSON string.
    static func string<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Prints `value` as JSON to stdout.
    static func emit<T: Encodable>(_ value: T) throws {
        print(try string(value))
    }
}
