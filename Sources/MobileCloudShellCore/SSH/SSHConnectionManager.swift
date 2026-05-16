import Foundation

public enum SSHConnectionError: Error, Equatable, LocalizedError, Sendable {
    case environmentNotConnectable
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .environmentNotConnectable:
            return "Cloud Shell environment does not include a complete SSH endpoint."
        case .invalidPort(let port):
            return "Cloud Shell SSH endpoint port is invalid: \(port)."
        }
    }
}

public struct SSHEndpoint: Equatable, Sendable {
    public let username: String
    public let host: String
    public let port: Int

    public init(username: String, host: String, port: Int) throws {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty, !normalizedHost.isEmpty else {
            throw SSHConnectionError.environmentNotConnectable
        }
        guard (1...65_535).contains(port) else {
            throw SSHConnectionError.invalidPort(port)
        }

        self.username = normalizedUsername
        self.host = normalizedHost
        self.port = port
    }

    public init(environment: CloudShellEnvironment) throws {
        guard let username = environment.sshUsername,
              let host = environment.sshHost,
              let port = environment.sshPort else {
            throw SSHConnectionError.environmentNotConnectable
        }
        try self.init(username: username, host: host, port: port)
    }
}

public struct SSHConnectionCredential: Equatable, Sendable {
    public let privateKey: SSHPrivateKeyMaterial

    public init(privateKey: SSHPrivateKeyMaterial) {
        self.privateKey = privateKey
    }
}

public struct SSHConnectionConfiguration: Equatable, Sendable {
    public let endpoint: SSHEndpoint
    public let credential: SSHConnectionCredential

    public init(endpoint: SSHEndpoint, credential: SSHConnectionCredential) {
        self.endpoint = endpoint
        self.credential = credential
    }

    public init(endpoint: SSHEndpoint, privateKey: SSHPrivateKeyMaterial) {
        self.init(endpoint: endpoint, credential: SSHConnectionCredential(privateKey: privateKey))
    }
}

public struct SSHConnectionManager {
    private let client: any SSHClientProtocol

    public init(client: any SSHClientProtocol) {
        self.client = client
    }

    public func connect(
        to environment: CloudShellEnvironment,
        using privateKey: SSHPrivateKeyMaterial
    ) async throws -> any SSHConnectionProtocol {
        let endpoint = try SSHEndpoint(environment: environment)
        return try await connect(to: endpoint, using: privateKey)
    }

    public func connect(
        to endpoint: SSHEndpoint,
        using privateKey: SSHPrivateKeyMaterial
    ) async throws -> any SSHConnectionProtocol {
        let configuration = SSHConnectionConfiguration(endpoint: endpoint, privateKey: privateKey)
        return try await client.connect(configuration: configuration)
    }

    public func execute(
        _ command: String,
        on environment: CloudShellEnvironment,
        using privateKey: SSHPrivateKeyMaterial
    ) async throws -> SSHExecResult {
        let connection = try await connect(to: environment, using: privateKey)
        do {
            let result = try await connection.execute(command)
            try await connection.close()
            return result
        } catch {
            try? await connection.close()
            throw error
        }
    }

    public func openPTY(
        on environment: CloudShellEnvironment,
        using privateKey: SSHPrivateKeyMaterial,
        request: SSHPTYRequest = SSHPTYRequest()
    ) async throws -> any SSHPTYChannelProtocol {
        let connection = try await connect(to: environment, using: privateKey)
        do {
            let channel = try await connection.openPTY(request)
            return SSHManagedPTYChannel(connection: connection, channel: channel)
        } catch {
            try? await connection.close()
            throw error
        }
    }
}

public final class SSHManagedPTYChannel: SSHPTYChannelProtocol {
    private let connection: any SSHConnectionProtocol
    private let channel: any SSHPTYChannelProtocol

    public init(connection: any SSHConnectionProtocol, channel: any SSHPTYChannelProtocol) {
        self.connection = connection
        self.channel = channel
    }

    public func write(_ data: Data) async throws {
        try await channel.write(data)
    }

    public func read(maxBytes: Int) async throws -> Data {
        try await channel.read(maxBytes: maxBytes)
    }

    public func close() async throws {
        do {
            try await channel.close()
            try await connection.close()
        } catch {
            try? await connection.close()
            throw error
        }
    }
}
