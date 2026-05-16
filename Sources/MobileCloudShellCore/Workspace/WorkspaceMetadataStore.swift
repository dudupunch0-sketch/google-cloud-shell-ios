import Foundation

public struct WorkspaceMetadataFile: Codable, Equatable, Sendable {
    public static let empty = WorkspaceMetadataFile(schemaVersion: 1, workspaces: [:])

    public let schemaVersion: Int
    public var workspaces: [String: WorkspaceMetadata]

    public init(schemaVersion: Int = 1, workspaces: [String: WorkspaceMetadata]) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
    }
}

public struct WorkspaceMetadata: Codable, Equatable, Sendable {
    public var displayName: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var lastOpenedAt: Date?

    public init(
        displayName: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct WorkspaceMetadataStore: Sendable {
    public enum StoreError: Error, Equatable, LocalizedError, Sendable {
        case unsupportedSchemaVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                return "Unsupported workspace metadata schema version: \(version)."
            }
        }
    }

    public init() {}

    public func decode(_ data: Data) throws -> WorkspaceMetadataFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceMetadataFile.self, from: data)
        guard decoded.schemaVersion == 1 else {
            throw StoreError.unsupportedSchemaVersion(decoded.schemaVersion)
        }
        return decoded
    }

    public func encode(_ metadata: WorkspaceMetadataFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metadata)
    }

    public func merge(liveSessions: [TmuxSession], metadata: WorkspaceMetadataFile) -> [Workspace] {
        liveSessions.map { session in
            let sessionMetadata = metadata.workspaces[session.name]
            return Workspace(
                sessionName: session.name,
                displayName: sessionMetadata?.displayName ?? WorkspaceDisplayName.fallback(for: session.name),
                createdAt: sessionMetadata?.createdAt ?? session.createdAt,
                lastActivityAt: session.lastActivityAt,
                windowCount: session.windowCount,
                attachedClientCount: session.attachedClientCount,
                lastOpenedAt: sessionMetadata?.lastOpenedAt
            )
        }
    }
}
