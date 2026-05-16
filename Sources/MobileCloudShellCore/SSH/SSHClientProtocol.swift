import Foundation

public protocol SSHClientProtocol {
    func connect(configuration: SSHConnectionConfiguration) async throws -> any SSHConnectionProtocol
}

public protocol SSHConnectionProtocol: AnyObject {
    func execute(_ command: String) async throws -> SSHExecResult
    func openPTY(_ request: SSHPTYRequest) async throws -> any SSHPTYChannelProtocol
    func close() async throws
}

public protocol SSHPTYChannelProtocol: AnyObject {
    func write(_ data: Data) async throws
    func read(maxBytes: Int) async throws -> Data
    func close() async throws
}

public struct SSHExecResult: Equatable, Sendable {
    public let exitStatus: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitStatus: Int32, stdout: Data = Data(), stderr: Data = Data()) {
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct SSHPTYRequest: Equatable, Sendable {
    public let terminalType: String
    public let columns: Int
    public let rows: Int
    public let widthPixels: Int
    public let heightPixels: Int

    public init(
        terminalType: String = "xterm-256color",
        columns: Int = 80,
        rows: Int = 24,
        widthPixels: Int = 0,
        heightPixels: Int = 0
    ) {
        self.terminalType = terminalType
        self.columns = columns
        self.rows = rows
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
    }
}
