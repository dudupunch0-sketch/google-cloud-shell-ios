import Foundation
import XCTest
@testable import MobileCloudShellCore

final class WorkspaceRepositoryTests: XCTestCase {
    func testListLiveWorkspacesRunsManagementCommandsAndMergesMetadata() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "tmux list-sessions",
                result: SSHExecResult(
                    exitStatus: 0,
                    stdout: Data("mobile-agent_20260516-1530_a|1778935800|1778935900|2|1\n0|1778935800|1778935900|1|0\n".utf8)
                )
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data(Self.metadataJSON.utf8))
            )
        ])
        let repository = WorkspaceRepository(executor: executor)

        let workspaces = try await repository.listLiveWorkspaces()

        XCTAssertEqual(executor.commands.count, 2)
        XCTAssertTrue(executor.commands[0].hasPrefix("tmux list-sessions"))
        XCTAssertTrue(executor.commands[1].hasPrefix("if [ -f ~/.mobile-cloud-shell/workspaces.json ]"))
        XCTAssertEqual(workspaces, [
            Workspace(
                sessionName: "mobile-agent_20260516-1530_a",
                displayName: "Codex: iOS PRD 정리",
                createdAt: fixedDate("2026-05-16T06:30:00Z"),
                lastActivityAt: Date(timeIntervalSince1970: 1_778_935_900),
                windowCount: 2,
                attachedClientCount: 1,
                lastOpenedAt: fixedDate("2026-05-16T07:01:03Z")
            )
        ])
    }

    func testCreateWorkspaceAllocatesNextNameCreatesTmuxSessionAndPersistsMetadata() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "tmux list-sessions",
                result: SSHExecResult(
                    exitStatus: 0,
                    stdout: Data("mobile-agent_20260516-1530_a|1778935800|1778935900|1|0\n".utf8)
                )
            ),
            .success(
                commandPrefix: "tmux new-session -d -s 'mobile-agent_20260516-1530_b'",
                result: SSHExecResult(exitStatus: 0)
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data("{\"schemaVersion\":1,\"workspaces\":{}}".utf8))
            ),
            .success(
                commandPrefix: "umask 077 && mkdir -p ~/.mobile-cloud-shell && chmod 700 ~/.mobile-cloud-shell && tmp=$(mktemp ~/.mobile-cloud-shell/workspaces.json.tmp.XXXXXX) && printf %s",
                result: SSHExecResult(exitStatus: 0)
            )
        ])
        let repository = WorkspaceRepository(
            executor: executor,
            now: { fixedDate("2026-05-16T15:30:30Z") }
        )

        let workspace = try await repository.createWorkspace(displayName: "New Workspace")

        XCTAssertEqual(workspace.sessionName, "mobile-agent_20260516-1530_b")
        XCTAssertEqual(workspace.displayName, "New Workspace")
        XCTAssertEqual(workspace.createdAt, fixedDate("2026-05-16T15:30:30Z"))
        XCTAssertEqual(workspace.lastActivityAt, fixedDate("2026-05-16T15:30:30Z"))
        XCTAssertEqual(workspace.windowCount, 1)
        XCTAssertEqual(workspace.attachedClientCount, 0)
        XCTAssertEqual(workspace.lastOpenedAt, fixedDate("2026-05-16T15:30:30Z"))
        XCTAssertEqual(executor.commands.count, 4)
        XCTAssertEqual(executor.commands[1], "tmux new-session -d -s 'mobile-agent_20260516-1530_b'")
        XCTAssertTrue(executor.commands[3].contains("New Workspace"))
        XCTAssertTrue(executor.commands[3].contains("mobile-agent_20260516-1530_b"))
        XCTAssertTrue(executor.commands[3].contains("workspaces.json.tmp"))
    }

    func testRenameWorkspaceUpdatesMetadataWithoutTmuxCommand() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data(Self.metadataJSON.utf8))
            ),
            .success(
                commandPrefix: "umask 077 && mkdir -p ~/.mobile-cloud-shell && chmod 700 ~/.mobile-cloud-shell && tmp=$(mktemp ~/.mobile-cloud-shell/workspaces.json.tmp.XXXXXX) && printf %s",
                result: SSHExecResult(exitStatus: 0)
            )
        ])
        let repository = WorkspaceRepository(
            executor: executor,
            now: { fixedDate("2026-05-16T08:00:00Z") }
        )

        try await repository.renameWorkspace(
            sessionName: "mobile-agent_20260516-1530_a",
            displayName: "Renamed Workspace"
        )

        XCTAssertEqual(executor.commands.count, 2)
        XCTAssertFalse(executor.commands.contains { $0.hasPrefix("tmux") })
        XCTAssertTrue(executor.commands[1].contains("Renamed Workspace"))
        XCTAssertTrue(executor.commands[1].contains("2026-05-16T08:00:00Z"))
    }

    func testKillWorkspaceKillsTmuxSessionThenRemovesMetadata() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "tmux kill-session -t 'mobile-agent_20260516-1530_a'",
                result: SSHExecResult(exitStatus: 0)
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data(Self.metadataJSON.utf8))
            ),
            .success(
                commandPrefix: "umask 077 && mkdir -p ~/.mobile-cloud-shell && chmod 700 ~/.mobile-cloud-shell && tmp=$(mktemp ~/.mobile-cloud-shell/workspaces.json.tmp.XXXXXX) && printf %s",
                result: SSHExecResult(exitStatus: 0)
            )
        ])
        let repository = WorkspaceRepository(executor: executor)

        try await repository.killWorkspace(sessionName: "mobile-agent_20260516-1530_a")

        XCTAssertEqual(executor.commands[0], "tmux kill-session -t 'mobile-agent_20260516-1530_a'")
        XCTAssertFalse(executor.commands[2].contains("mobile-agent_20260516-1530_a"))
    }

    func testCreateWorkspaceBacksUpMalformedMetadataBeforeReplacingIt() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "tmux list-sessions",
                result: SSHExecResult(exitStatus: 0, stdout: Data())
            ),
            .success(
                commandPrefix: "tmux new-session -d -s 'mobile-agent_20260516-1530_a'",
                result: SSHExecResult(exitStatus: 0)
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data("not-json".utf8))
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]; then umask 077 && mkdir -p ~/.mobile-cloud-shell && chmod 700 ~/.mobile-cloud-shell && mv",
                result: SSHExecResult(exitStatus: 0)
            ),
            .success(
                commandPrefix: "umask 077 && mkdir -p ~/.mobile-cloud-shell && chmod 700 ~/.mobile-cloud-shell && tmp=$(mktemp ~/.mobile-cloud-shell/workspaces.json.tmp.XXXXXX) && printf %s",
                result: SSHExecResult(exitStatus: 0)
            )
        ])
        let repository = WorkspaceRepository(
            executor: executor,
            now: { fixedDate("2026-05-16T15:30:00Z") }
        )

        let workspace = try await repository.createWorkspace(displayName: nil)

        XCTAssertEqual(workspace.displayName, "Workspace 15:30 a")
        XCTAssertEqual(executor.commands.count, 5)
        XCTAssertTrue(executor.commands[3].contains("workspaces.json.invalid.$(date +%Y%m%d%H%M%S)"))
        XCTAssertTrue(executor.commands[4].contains("mobile-agent_20260516-1530_a"))
    }

    func testRepositoryRejectsUnmanagedSessionNamesBeforeBuildingCommands() async {
        let executor = RecordingWorkspaceExecutor(responses: [])
        let repository = WorkspaceRepository(executor: executor)

        do {
            try await repository.renameWorkspace(
                sessionName: "mobile-agent_20260516-1530_a;tmux kill-server",
                displayName: "Bad"
            )
            XCTFail("Expected invalid session name error")
        } catch let error as WorkspaceRepositoryError {
            XCTAssertEqual(error, .invalidSessionName("mobile-agent_20260516-1530_a;tmux kill-server"))
        } catch {
            XCTFail("Expected WorkspaceRepositoryError, got \(error)")
        }

        XCTAssertTrue(executor.commands.isEmpty)
    }

    func testListLiveWorkspacesTreatsMissingTmuxServerAsEmptyList() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "tmux list-sessions",
                result: SSHExecResult(
                    exitStatus: 1,
                    stderr: Data("no server running on /tmp/tmux-501/default".utf8)
                )
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data(Self.metadataJSON.utf8))
            )
        ])
        let repository = WorkspaceRepository(executor: executor)

        let workspaces = try await repository.listLiveWorkspaces()

        XCTAssertEqual(workspaces, [])
        XCTAssertEqual(executor.commands.count, 2)
    }

    func testWriteMetadataCommandFailureDoesNotExposeMetadataJSONInErrorDescription() async throws {
        let executor = RecordingWorkspaceExecutor(responses: [
            .success(
                commandPrefix: "tmux list-sessions",
                result: SSHExecResult(exitStatus: 0, stdout: Data())
            ),
            .success(
                commandPrefix: "tmux new-session -d -s 'mobile-agent_20260516-1530_a'",
                result: SSHExecResult(exitStatus: 0)
            ),
            .success(
                commandPrefix: "if [ -f ~/.mobile-cloud-shell/workspaces.json ]",
                result: SSHExecResult(exitStatus: 0, stdout: Data("{\"schemaVersion\":1,\"workspaces\":{}}".utf8))
            ),
            .success(
                commandPrefix: "umask 077 && mkdir -p ~/.mobile-cloud-shell && chmod 700 ~/.mobile-cloud-shell && tmp=$(mktemp ~/.mobile-cloud-shell/workspaces.json.tmp.XXXXXX) && printf %s",
                result: SSHExecResult(exitStatus: 7, stderr: Data("disk full".utf8))
            )
        ])
        let repository = WorkspaceRepository(
            executor: executor,
            now: { fixedDate("2026-05-16T15:30:00Z") }
        )

        do {
            _ = try await repository.createWorkspace(displayName: "Sensitive Project Name")
            XCTFail("Expected write metadata failure")
        } catch let error as WorkspaceRepositoryError {
            XCTAssertEqual(
                error,
                .commandFailed(operation: "write workspace metadata", exitStatus: 7, stderr: "disk full")
            )
            XCTAssertTrue(error.localizedDescription.contains("write workspace metadata"))
            XCTAssertFalse(error.localizedDescription.contains("Sensitive Project Name"))
            XCTAssertFalse(error.localizedDescription.contains("mobile-agent_20260516-1530_a"))
        } catch {
            XCTFail("Expected WorkspaceRepositoryError, got \(error)")
        }
    }

    private static let metadataJSON = """
    {
      "schemaVersion": 1,
      "workspaces": {
        "mobile-agent_20260516-1530_a": {
          "displayName": "Codex: iOS PRD 정리",
          "createdAt": "2026-05-16T06:30:00Z",
          "updatedAt": "2026-05-16T06:45:12Z",
          "lastOpenedAt": "2026-05-16T07:01:03Z"
        }
      }
    }
    """
}

private final class RecordingWorkspaceExecutor: WorkspaceManagementExecuting {
    private(set) var commands: [String] = []
    private var responses: [RecordedWorkspaceResponse]

    init(responses: [RecordedWorkspaceResponse]) {
        self.responses = responses
    }

    func execute(_ command: String) async throws -> SSHExecResult {
        commands.append(command)
        guard !responses.isEmpty else {
            throw RecordingWorkspaceExecutorError.unexpectedCommand(command)
        }
        let response = responses.removeFirst()
        guard command.hasPrefix(response.commandPrefix) else {
            throw RecordingWorkspaceExecutorError.commandMismatch(
                expectedPrefix: response.commandPrefix,
                actual: command
            )
        }
        switch response.outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

private struct RecordedWorkspaceResponse {
    let commandPrefix: String
    let outcome: Outcome

    static func success(commandPrefix: String, result: SSHExecResult) -> RecordedWorkspaceResponse {
        RecordedWorkspaceResponse(commandPrefix: commandPrefix, outcome: .success(result))
    }

    static func failure(commandPrefix: String, error: Error) -> RecordedWorkspaceResponse {
        RecordedWorkspaceResponse(commandPrefix: commandPrefix, outcome: .failure(error))
    }

    enum Outcome {
        case success(SSHExecResult)
        case failure(Error)
    }
}

private enum RecordingWorkspaceExecutorError: Error, Equatable {
    case unexpectedCommand(String)
    case commandMismatch(expectedPrefix: String, actual: String)
}

private func fixedDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value)!
}
