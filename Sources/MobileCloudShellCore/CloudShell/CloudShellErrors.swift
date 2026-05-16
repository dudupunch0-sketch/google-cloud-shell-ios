import Foundation

public struct CloudShellOperationError: Codable, Equatable, Sendable {
    public let code: Int?
    public let message: String?
    public let status: String?

    public init(code: Int? = nil, message: String? = nil, status: String? = nil) {
        self.code = code
        self.message = message.map(RedactedLogger.redact)
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decodeIfPresent(Int.self, forKey: .code)
        self.message = try container.decodeIfPresent(String.self, forKey: .message).map(RedactedLogger.redact)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(status, forKey: .status)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case status
    }
}

public enum CloudShellError: Error, Equatable, LocalizedError, Sendable {
    case unauthorized
    case forbidden(message: String?)
    case quotaExceeded(message: String?)
    case unavailable(message: String?)
    case unexpectedStatus(code: Int, message: String?)
    case invalidResponse
    case timedOut(operationName: String, attempts: Int)
    case operationFailed(CloudShellOperationError)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Cloud Shell request is unauthorized."
        case .forbidden(let message):
            return message.map(RedactedLogger.redact) ?? "Cloud Shell request is forbidden."
        case .quotaExceeded(let message):
            return message.map(RedactedLogger.redact) ?? "Cloud Shell quota exceeded."
        case .unavailable(let message):
            return message.map(RedactedLogger.redact) ?? "Cloud Shell service is unavailable."
        case .unexpectedStatus(let code, let message):
            if let message {
                return "Unexpected Cloud Shell status \(code): \(RedactedLogger.redact(message))"
            }
            return "Unexpected Cloud Shell status \(code)."
        case .invalidResponse:
            return "Cloud Shell response was invalid."
        case .timedOut(let operationName, let attempts):
            return "Cloud Shell operation \(operationName) did not complete after \(attempts) attempts."
        case .operationFailed(let error):
            return error.message.map(RedactedLogger.redact) ?? "Cloud Shell operation failed."
        }
    }
}
