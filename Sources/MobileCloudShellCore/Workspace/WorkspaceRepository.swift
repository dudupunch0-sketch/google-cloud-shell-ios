import Foundation

public protocol WorkspaceManagementExecuting {
    func execute(_ command: String) async throws -> SSHExecResult
}

public enum WorkspaceRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidSessionName(String)
    case commandFailed(operation: String, exitStatus: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSessionName(let sessionName):
            return "Workspace session name is not app-managed or is malformed: \(sessionName)."
        case .commandFailed(let operation, let exitStatus, let stderr):
            if stderr.isEmpty {
                return "Workspace management operation failed with exit status \(exitStatus): \(operation)."
            }
            return "Workspace management operation failed with exit status \(exitStatus): \(operation). stderr: \(stderr)"
        }
    }
}

public struct SSHWorkspaceManagementExecutor: WorkspaceManagementExecuting {
    private let connectionManager: SSHConnectionManager
    private let environment: CloudShellEnvironment
    private let privateKey: SSHPrivateKeyMaterial

    public init(
        connectionManager: SSHConnectionManager,
        environment: CloudShellEnvironment,
        privateKey: SSHPrivateKeyMaterial
    ) {
        self.connectionManager = connectionManager
        self.environment = environment
        self.privateKey = privateKey
    }

    public func execute(_ command: String) async throws -> SSHExecResult {
        try await connectionManager.execute(command, on: environment, using: privateKey)
    }
}

public struct WorkspaceRepository {
    private let executor: any WorkspaceManagementExecuting
    private let parser: TmuxSessionParser
    private let metadataStore: WorkspaceMetadataStore
    private let nameGenerator: WorkspaceNameGenerator
    private let now: () -> Date

    public init(
        executor: any WorkspaceManagementExecuting,
        parser: TmuxSessionParser = TmuxSessionParser(),
        metadataStore: WorkspaceMetadataStore = WorkspaceMetadataStore(),
        nameGenerator: WorkspaceNameGenerator = WorkspaceNameGenerator(),
        now: @escaping () -> Date = Date.init
    ) {
        self.executor = executor
        self.parser = parser
        self.metadataStore = metadataStore
        self.nameGenerator = nameGenerator
        self.now = now
    }

    public func listLiveWorkspaces() async throws -> [Workspace] {
        let sessions = try await loadLiveSessions()
        let metadata = try await loadMetadata(backingUpMalformedFile: false)
        return metadataStore.merge(liveSessions: sessions, metadata: metadata)
    }

    public func createWorkspace(displayName requestedDisplayName: String? = nil) async throws -> Workspace {
        let currentDate = now()
        let liveSessions = try await loadLiveSessions()
        let sessionName = try nameGenerator.makeName(
            for: currentDate,
            existingSessionNames: Set(liveSessions.map(\.name))
        )
        try await run(
            WorkspaceRepositoryCommands.createSession(sessionName: sessionName),
            operation: "create tmux workspace"
        )

        var metadata = try await loadMetadata(backingUpMalformedFile: true)
        let displayName = normalizedDisplayName(requestedDisplayName) ?? WorkspaceDisplayName.fallback(for: sessionName)
        metadata.workspaces[sessionName] = WorkspaceMetadata(
            displayName: displayName,
            createdAt: currentDate,
            updatedAt: currentDate,
            lastOpenedAt: currentDate
        )
        try await writeMetadata(metadata)

        return Workspace(
            sessionName: sessionName,
            displayName: displayName,
            createdAt: currentDate,
            lastActivityAt: currentDate,
            windowCount: 1,
            attachedClientCount: 0,
            lastOpenedAt: currentDate
        )
    }

    public func renameWorkspace(sessionName: String, displayName requestedDisplayName: String) async throws {
        try validateManagedSessionName(sessionName)
        var metadata = try await loadMetadata(backingUpMalformedFile: true)
        let currentDate = now()
        let displayName = normalizedDisplayName(requestedDisplayName) ?? WorkspaceDisplayName.fallback(for: sessionName)
        var sessionMetadata = metadata.workspaces[sessionName] ?? WorkspaceMetadata(displayName: displayName)
        sessionMetadata.displayName = displayName
        sessionMetadata.updatedAt = currentDate
        metadata.workspaces[sessionName] = sessionMetadata
        try await writeMetadata(metadata)
    }

    public func killWorkspace(sessionName: String) async throws {
        try validateManagedSessionName(sessionName)
        try await run(
            WorkspaceRepositoryCommands.killSession(sessionName: sessionName),
            operation: "kill tmux workspace"
        )
        var metadata = try await loadMetadata(backingUpMalformedFile: true)
        metadata.workspaces.removeValue(forKey: sessionName)
        try await writeMetadata(metadata)
    }

    private func loadLiveSessions() async throws -> [TmuxSession] {
        let result = try await executor.execute(WorkspaceRepositoryCommands.listSessions)
        guard result.exitStatus == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            if isMissingTmuxServer(exitStatus: result.exitStatus, stderr: stderr) {
                return []
            }
            throw WorkspaceRepositoryError.commandFailed(
                operation: "list tmux workspaces",
                exitStatus: result.exitStatus,
                stderr: stderr
            )
        }
        guard let output = String(data: result.stdout, encoding: .utf8) else {
            return []
        }
        return parser.parse(output)
    }

    private func isMissingTmuxServer(exitStatus: Int32, stderr: String) -> Bool {
        guard exitStatus == 1 else { return false }
        let normalizedStderr = stderr.lowercased()
        return normalizedStderr.contains("no server running") ||
            normalizedStderr.contains("failed to connect to server")
    }

    private func loadMetadata(backingUpMalformedFile: Bool) async throws -> WorkspaceMetadataFile {
        let result = try await run(WorkspaceRepositoryCommands.readMetadata, operation: "read workspace metadata")
        guard !result.stdout.isEmpty else {
            return .empty
        }
        if let text = String(data: result.stdout, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }

        do {
            return try metadataStore.decode(result.stdout)
        } catch {
            if backingUpMalformedFile {
                try await run(
                    WorkspaceRepositoryCommands.backupMalformedMetadata,
                    operation: "backup malformed workspace metadata"
                )
            }
            return .empty
        }
    }

    private func writeMetadata(_ metadata: WorkspaceMetadataFile) async throws {
        let data = try metadataStore.encode(metadata)
        let json = String(data: data, encoding: .utf8) ?? ""
        try await run(WorkspaceRepositoryCommands.writeMetadata(json: json), operation: "write workspace metadata")
    }

    @discardableResult
    private func run(_ command: String, operation: String) async throws -> SSHExecResult {
        let result = try await executor.execute(command)
        guard result.exitStatus == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            throw WorkspaceRepositoryError.commandFailed(
                operation: operation,
                exitStatus: result.exitStatus,
                stderr: stderr
            )
        }
        return result
    }

    private func validateManagedSessionName(_ sessionName: String) throws {
        guard WorkspaceNameGenerator.isManagedSessionName(sessionName) else {
            throw WorkspaceRepositoryError.invalidSessionName(sessionName)
        }
    }

    private func normalizedDisplayName(_ displayName: String?) -> String? {
        guard let displayName else { return nil }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum WorkspaceRepositoryCommands {
    private static let metadataDirectoryPath = "~/.mobile-cloud-shell"
    private static let metadataPath = "\(metadataDirectoryPath)/workspaces.json"
    private static let emptyMetadataJSON = "{\"schemaVersion\":1,\"workspaces\":{}}"

    static let listSessions = [
        "tmux",
        "list-sessions",
        "-F",
        SSHCommandQuoter.quote("#{session_name}|#{session_created}|#{session_activity}|#{session_windows}|#{session_attached}")
    ].joined(separator: " ")

    static let readMetadata = "if [ -f \(metadataPath) ]; then cat \(metadataPath); else printf %s \(SSHCommandQuoter.quote(emptyMetadataJSON)); fi"

    static let backupMalformedMetadata = "if [ -f \(metadataPath) ]; then umask 077 && mkdir -p \(metadataDirectoryPath) && chmod 700 \(metadataDirectoryPath) && mv \(metadataPath) \(metadataPath).invalid.$(date +%Y%m%d%H%M%S); fi"

    static func createSession(sessionName: String) -> String {
        "tmux new-session -d -s \(SSHCommandQuoter.quote(sessionName))"
    }

    static func killSession(sessionName: String) -> String {
        "tmux kill-session -t \(SSHCommandQuoter.quote(sessionName))"
    }

    static func writeMetadata(json: String) -> String {
        "umask 077 && mkdir -p \(metadataDirectoryPath) && chmod 700 \(metadataDirectoryPath) && tmp=$(mktemp \(metadataPath).tmp.XXXXXX) && printf %s \(SSHCommandQuoter.quote(json)) > \"$tmp\" && mv \"$tmp\" \(metadataPath)"
    }
}
