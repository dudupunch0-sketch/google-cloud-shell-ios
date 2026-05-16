import Foundation
import XCTest
@testable import MobileCloudShellCore

final class SSHConnectionManagerTests: XCTestCase {
    func testEnvironmentMapsToEndpointWhenConnectable() throws {
        let environment = CloudShellEnvironment(
            name: "users/me/environments/default",
            state: .running,
            sshUsername: " cloud-user ",
            sshHost: " ssh.cloudshell.dev ",
            sshPort: 6000
        )

        let endpoint = try SSHEndpoint(environment: environment)

        XCTAssertEqual(endpoint, try SSHEndpoint(username: "cloud-user", host: "ssh.cloudshell.dev", port: 6000))
    }

    func testEnvironmentDoesNotMapToEndpointWhenNotConnectable() {
        let environment = CloudShellEnvironment(
            name: "users/me/environments/default",
            state: .running,
            sshUsername: "cloud-user",
            sshHost: nil,
            sshPort: 6000
        )

        XCTAssertThrowsError(try SSHEndpoint(environment: environment)) { error in
            XCTAssertEqual(error as? SSHConnectionError, .environmentNotConnectable)
        }
    }

    func testEndpointRejectsInvalidDirectValues() {
        XCTAssertThrowsError(try SSHEndpoint(username: "", host: "ssh.cloudshell.dev", port: 6000)) { error in
            XCTAssertEqual(error as? SSHConnectionError, .environmentNotConnectable)
        }
        XCTAssertThrowsError(try SSHEndpoint(username: "cloud-user", host: "", port: 6000)) { error in
            XCTAssertEqual(error as? SSHConnectionError, .environmentNotConnectable)
        }
        XCTAssertThrowsError(try SSHEndpoint(username: "cloud-user", host: "ssh.cloudshell.dev", port: 0)) { error in
            XCTAssertEqual(error as? SSHConnectionError, .invalidPort(0))
        }
        XCTAssertThrowsError(try SSHEndpoint(username: "cloud-user", host: "ssh.cloudshell.dev", port: 65_536)) { error in
            XCTAssertEqual(error as? SSHConnectionError, .invalidPort(65_536))
        }
    }

    func testManagerPassesEndpointAndPrivateKeyToInjectedClient() async throws {
        let connection = RecordingSSHConnection()
        let client = RecordingSSHClient(connection: connection)
        let manager = SSHConnectionManager(client: client)
        let privateKey = try makeConnectionPrivateKey()
        let environment = connectableEnvironment()

        _ = try await manager.connect(to: environment, using: privateKey)

        let configuration = try XCTUnwrap(client.configurations.first)
        XCTAssertEqual(configuration.endpoint, try SSHEndpoint(username: "cloud-user", host: "ssh.cloudshell.dev", port: 6000))
        XCTAssertEqual(configuration.credential.privateKey, privateKey)
    }

    func testConnectionProtocolSeparatesExecAndPTYRequests() async throws {
        let connection = RecordingSSHConnection()
        let client = RecordingSSHClient(connection: connection)
        let manager = SSHConnectionManager(client: client)
        let privateKey = try makeConnectionPrivateKey()
        let connected = try await manager.connect(to: connectableEnvironment(), using: privateKey)

        let execResult = try await connected.execute("tmux list-sessions")
        let ptyRequest = SSHPTYRequest(terminalType: "xterm-256color", columns: 100, rows: 30)
        let ptyChannel = try await connected.openPTY(ptyRequest)
        try await ptyChannel.write(Data("input".utf8))

        XCTAssertEqual(execResult, SSHExecResult(exitStatus: 0, stdout: Data("ok".utf8), stderr: Data()))
        XCTAssertEqual(connection.executedCommands, ["tmux list-sessions"])
        XCTAssertEqual(connection.ptyRequests, [ptyRequest])
        XCTAssertEqual(connection.ptyChannel.writes, [Data("input".utf8)])
    }

    func testExecuteConvenienceClosesConnectionAfterCommand() async throws {
        let connection = RecordingSSHConnection()
        let manager = SSHConnectionManager(client: RecordingSSHClient(connection: connection))

        let result = try await manager.execute("tmux list-sessions", on: connectableEnvironment(), using: makeConnectionPrivateKey())

        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(connection.executedCommands, ["tmux list-sessions"])
        XCTAssertEqual(connection.closeCount, 1)
    }

    func testOpenPTYConvenienceReturnsManagedChannelThatClosesPTYAndConnection() async throws {
        let connection = RecordingSSHConnection()
        let manager = SSHConnectionManager(client: RecordingSSHClient(connection: connection))

        let channel = try await manager.openPTY(on: connectableEnvironment(), using: makeConnectionPrivateKey())
        try await channel.write(Data("input".utf8))
        try await channel.close()

        XCTAssertEqual(connection.ptyChannel.writes, [Data("input".utf8)])
        XCTAssertEqual(connection.ptyChannel.closeCount, 1)
        XCTAssertEqual(connection.closeCount, 1)
    }

    func testOpenPTYConvenienceClosesConnectionWhenPTYOpenFails() async throws {
        let connection = RecordingSSHConnection(openPTYError: SSHConnectionTestError.openPTYFailed)
        let manager = SSHConnectionManager(client: RecordingSSHClient(connection: connection))

        do {
            _ = try await manager.openPTY(on: connectableEnvironment(), using: makeConnectionPrivateKey())
            XCTFail("Expected PTY open failure")
        } catch let error as SSHConnectionTestError {
            XCTAssertEqual(error, .openPTYFailed)
        } catch {
            XCTFail("Expected SSHConnectionTestError, got \(error)")
        }

        XCTAssertEqual(connection.ptyRequests, [SSHPTYRequest()])
        XCTAssertEqual(connection.closeCount, 1)
    }
}

private enum SSHConnectionTestError: Error, Equatable {
    case openPTYFailed
}

private final class RecordingSSHClient: SSHClientProtocol {
    private(set) var configurations: [SSHConnectionConfiguration] = []
    private let connection: any SSHConnectionProtocol

    init(connection: any SSHConnectionProtocol) {
        self.connection = connection
    }

    func connect(configuration: SSHConnectionConfiguration) async throws -> any SSHConnectionProtocol {
        configurations.append(configuration)
        return connection
    }
}

private final class RecordingSSHConnection: SSHConnectionProtocol {
    private(set) var executedCommands: [String] = []
    private(set) var ptyRequests: [SSHPTYRequest] = []
    private(set) var closeCount = 0
    private let openPTYError: Error?
    let ptyChannel = RecordingSSHPTYChannel()

    init(openPTYError: Error? = nil) {
        self.openPTYError = openPTYError
    }

    func execute(_ command: String) async throws -> SSHExecResult {
        executedCommands.append(command)
        return SSHExecResult(exitStatus: 0, stdout: Data("ok".utf8), stderr: Data())
    }

    func openPTY(_ request: SSHPTYRequest) async throws -> any SSHPTYChannelProtocol {
        ptyRequests.append(request)
        if let openPTYError { throw openPTYError }
        return ptyChannel
    }

    func close() async throws {
        closeCount += 1
    }
}

private final class RecordingSSHPTYChannel: SSHPTYChannelProtocol {
    private(set) var writes: [Data] = []
    private(set) var closeCount = 0

    func write(_ data: Data) async throws {
        writes.append(data)
    }

    func read(maxBytes: Int) async throws -> Data {
        Data()
    }

    func close() async throws {
        closeCount += 1
    }
}

private func connectableEnvironment() -> CloudShellEnvironment {
    CloudShellEnvironment(
        name: "users/me/environments/default",
        state: .running,
        sshUsername: "cloud-user",
        sshHost: "ssh.cloudshell.dev",
        sshPort: 6000
    )
}

private func makeConnectionPrivateKey() throws -> SSHPrivateKeyMaterial {
    try SSHPrivateKeyMaterial(
        pemString: """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAcHJpdmF0ZS1rZXktbWF0ZXJpYWw=
        -----END OPENSSH PRIVATE KEY-----
        """
    )
}
