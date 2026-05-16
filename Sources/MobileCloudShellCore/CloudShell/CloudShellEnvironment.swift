import Foundation

public struct CloudShellEnvironment: Equatable, Sendable {
    public enum State: Equatable, Codable, Sendable {
        case unspecified
        case suspended
        case pending
        case running
        case deleting
        case unknown

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self = Self(apiValue: value)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(apiValue)
        }

        public init(apiValue: String) {
            switch apiValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "unspecified", "state_unspecified":
                self = .unspecified
            case "suspended":
                self = .suspended
            case "pending":
                self = .pending
            case "running":
                self = .running
            case "deleting":
                self = .deleting
            default:
                self = .unknown
            }
        }

        public var apiValue: String {
            switch self {
            case .unspecified:
                return "STATE_UNSPECIFIED"
            case .suspended:
                return "SUSPENDED"
            case .pending:
                return "PENDING"
            case .running:
                return "RUNNING"
            case .deleting:
                return "DELETING"
            case .unknown:
                return "UNKNOWN"
            }
        }
    }

    public let name: String
    public let state: State
    public let sshUsername: String?
    public let sshHost: String?
    public let sshPort: Int?

    public init(
        name: String,
        state: State,
        sshUsername: String? = nil,
        sshHost: String? = nil,
        sshPort: Int? = nil
    ) {
        self.name = name
        self.state = state
        self.sshUsername = sshUsername
        self.sshHost = sshHost
        self.sshPort = sshPort
    }

    public var isSSHConnectable: Bool {
        sshUsername?.isEmpty == false &&
            sshHost?.isEmpty == false &&
            sshPort != nil
    }
}
