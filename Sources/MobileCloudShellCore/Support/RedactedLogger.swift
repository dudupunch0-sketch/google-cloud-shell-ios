import Foundation

public struct RedactedLogger {
    public typealias Sink = (String) -> Void

    public static let redactionMarker = "<redacted>"

    private let sink: Sink

    public init(sink: @escaping Sink = { print($0) }) {
        self.sink = sink
    }

    public func log(_ message: String) {
        sink(Self.redact(message))
    }

    public static func redact(_ message: String) -> String {
        var redacted = message
        redacted = replace(
            pattern: #"(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#,
            in: redacted,
            with: "-----BEGIN PRIVATE KEY-----\n\(redactionMarker)\n-----END PRIVATE KEY-----"
        )
        redacted = replace(
            pattern: #"(?i)((?:Authorization|authorization)[\s"']*[:=][\s"']*Bearer\s+)[^\s"',}\]]+"#,
            in: redacted,
            with: "$1" + redactionMarker
        )
        redacted = replace(
            pattern: #"(?i)(\bBearer\s+)[^\s"',}\]]+"#,
            in: redacted,
            with: "$1" + redactionMarker
        )
        redacted = replace(
            pattern: #"(?i)((?:["'])?\b(?:access_token|id_token|refresh_token|accessToken|idToken|refreshToken)\b(?:["'])?\s*[:=]\s*["']?)[^\s"',}&]+(["']?)"#,
            in: redacted,
            with: "$1" + redactionMarker + "$2"
        )
        return redacted
    }

    private static func replace(pattern: String, in input: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }
}
