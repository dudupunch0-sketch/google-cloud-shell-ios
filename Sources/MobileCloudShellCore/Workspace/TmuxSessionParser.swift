import Foundation

public struct TmuxSession: Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let createdAt: Date
    public let lastActivityAt: Date
    public let windowCount: Int
    public let attachedClientCount: Int

    public init(
        name: String,
        createdAt: Date,
        lastActivityAt: Date,
        windowCount: Int,
        attachedClientCount: Int
    ) {
        self.name = name
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.windowCount = windowCount
        self.attachedClientCount = attachedClientCount
    }
}

public struct TmuxSessionParser: Sendable {
    public init() {}

    public func parse(_ output: String) -> [TmuxSession] {
        output
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .compactMap(parseLine)
    }

    private func parseLine(_ line: Substring) -> TmuxSession? {
        let fields = line.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 5 else { return nil }

        let name = String(fields[0])
        guard WorkspaceNameGenerator.isManagedSessionName(name) else { return nil }
        guard
            let createdEpoch = Int(fields[1]),
            let activityEpoch = Int(fields[2]),
            let windowCount = Int(fields[3]),
            let attachedClientCount = Int(fields[4])
        else {
            return nil
        }

        return TmuxSession(
            name: name,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdEpoch)),
            lastActivityAt: Date(timeIntervalSince1970: TimeInterval(activityEpoch)),
            windowCount: windowCount,
            attachedClientCount: attachedClientCount
        )
    }
}
