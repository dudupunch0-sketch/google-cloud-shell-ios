import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CloudShellAPIClient: OperationFetching {
    public typealias AccessTokenProvider = @Sendable () async throws -> String

    public static let defaultBaseURL = URL(string: "https://cloudshell.googleapis.com/v1")!

    private let baseURL: URL
    private let httpClient: any HTTPClient
    private let accessTokenProvider: AccessTokenProvider

    public init(
        baseURL: URL = CloudShellAPIClient.defaultBaseURL,
        httpClient: any HTTPClient,
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.accessTokenProvider = accessTokenProvider
    }

    public func getDefaultEnvironment() async throws -> CloudShellEnvironment {
        let dto: CloudShellEnvironmentDTO = try await send(
            path: "users/me/environments/default",
            method: "GET",
            responseType: CloudShellEnvironmentDTO.self
        )
        return dto.domain
    }

    public func startDefaultEnvironment(
        accessToken: String? = nil,
        publicKeys: [String] = []
    ) async throws -> CloudShellOperation {
        let body = try Self.encode(
            StartEnvironmentRequestDTO(
                accessToken: accessToken,
                publicKeys: publicKeys.isEmpty ? nil : publicKeys
            )
        )
        let dto: CloudShellOperationDTO = try await send(
            path: "users/me/environments/default:start",
            method: "POST",
            body: body,
            responseType: CloudShellOperationDTO.self
        )
        return dto.domain
    }

    public func addPublicKey(_ key: String) async throws -> CloudShellOperation {
        let body = try Self.encode(AddPublicKeyRequestDTO(key: key))
        let dto: CloudShellOperationDTO = try await send(
            path: "users/me/environments/default:addPublicKey",
            method: "POST",
            body: body,
            responseType: CloudShellOperationDTO.self
        )
        return dto.domain
    }

    public func authorizeDefaultEnvironment(with session: AuthSession) async throws -> CloudShellOperation {
        let body = try Self.encode(
            AuthorizeEnvironmentRequestDTO(
                accessToken: session.accessToken,
                idToken: session.idToken,
                expireTime: session.expiresAt
            )
        )
        let dto: CloudShellOperationDTO = try await send(
            path: "users/me/environments/default:authorize",
            method: "POST",
            body: body,
            responseType: CloudShellOperationDTO.self
        )
        return dto.domain
    }

    public func fetchOperation(named name: String) async throws -> CloudShellOperation {
        let dto: CloudShellOperationDTO = try await send(
            path: name,
            method: "GET",
            responseType: CloudShellOperationDTO.self
        )
        return dto.domain
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await accessTokenProvider())", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapStatusError(statusCode: response.statusCode, data: data)
        }

        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw CloudShellError.invalidResponse
        }
    }

    private func makeURL(path: String) -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { Self.percentEncodePathSegment(String($0)) }
            .joined(separator: "/")
        return URL(string: "\(base)/\(encodedPath)")!
    }

    private static func percentEncodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try makeEncoder().encode(value)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func mapStatusError(statusCode: Int, data: Data) -> CloudShellError {
        let message = errorMessage(from: data)
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message: message)
        case 429:
            return .quotaExceeded(message: message)
        case 503:
            return .unavailable(message: message)
        default:
            return .unexpectedStatus(code: statusCode, message: message)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        if let envelope = try? makeDecoder().decode(CloudShellErrorEnvelopeDTO.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return RedactedLogger.redact(message)
        }
        if let message = String(data: data, encoding: .utf8), !message.isEmpty {
            return RedactedLogger.redact(message)
        }
        return nil
    }
}

private struct CloudShellEnvironmentDTO: Decodable {
    let name: String
    let state: CloudShellEnvironment.State?
    let sshUsername: String?
    let sshHost: String?
    let sshPort: Int?

    var domain: CloudShellEnvironment {
        CloudShellEnvironment(
            name: name,
            state: state ?? .unspecified,
            sshUsername: sshUsername,
            sshHost: sshHost,
            sshPort: sshPort
        )
    }
}

private struct CloudShellOperationDTO: Decodable {
    let name: String
    let done: Bool?
    let error: CloudShellOperationError?

    var domain: CloudShellOperation {
        CloudShellOperation(name: name, done: done ?? false, error: error)
    }
}

private struct StartEnvironmentRequestDTO: Encodable {
    let accessToken: String?
    let publicKeys: [String]?
}

private struct AddPublicKeyRequestDTO: Encodable {
    let key: String
}

private struct AuthorizeEnvironmentRequestDTO: Encodable {
    let accessToken: String
    let idToken: String?
    let expireTime: Date
}

private struct CloudShellErrorEnvelopeDTO: Decodable {
    let error: CloudShellErrorMessageDTO?
}

private struct CloudShellErrorMessageDTO: Decodable {
    let message: String?
}
