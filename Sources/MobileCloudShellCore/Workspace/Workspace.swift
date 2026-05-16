import Foundation

public struct Workspace: Equatable, Identifiable, Sendable {
    public var id: String { sessionName }

    public let sessionName: String
    public var displayName: String
    public let createdAt: Date?
    public let lastActivityAt: Date?
    public let windowCount: Int
    public let attachedClientCount: Int
    public var lastOpenedAt: Date?

    public init(
        sessionName: String,
        displayName: String,
        createdAt: Date?,
        lastActivityAt: Date?,
        windowCount: Int,
        attachedClientCount: Int,
        lastOpenedAt: Date? = nil
    ) {
        self.sessionName = sessionName
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.windowCount = windowCount
        self.attachedClientCount = attachedClientCount
        self.lastOpenedAt = lastOpenedAt
    }
}

enum WorkspaceDisplayName {
    static func fallback(for sessionName: String) -> String {
        guard WorkspaceNameGenerator.isManagedSessionName(sessionName) else { return sessionName }

        let expectedPrefix = "\(WorkspaceNameGenerator.managedPrefix)_"
        let rest = sessionName.dropFirst(expectedPrefix.count)
        let pieces = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return sessionName }

        let timestamp = pieces[0]
        let suffix = pieces[1]
        guard let dash = timestamp.firstIndex(of: "-") else { return sessionName }

        let timeStart = timestamp.index(after: dash)
        let timePart = timestamp[timeStart...]
        guard timePart.count == 4 else { return sessionName }

        let hour = timePart.prefix(2)
        let minute = timePart.suffix(2)
        return "Workspace \(hour):\(minute) \(suffix)"
    }
}
