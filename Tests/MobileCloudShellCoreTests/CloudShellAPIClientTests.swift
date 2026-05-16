import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import MobileCloudShellCore

final class CloudShellAPIClientTests: XCTestCase {
    func testGetDefaultEnvironmentSendsBearerHeaderAndDecodesEnvironment() async throws {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: """
            {
              "name": "users/me/environments/default",
              "state": "RUNNING",
              "sshUsername": "cloud-user",
              "sshHost": "ssh.cloudshell.dev",
              "sshPort": 6000
            }
            """)
        ])
        let client = makeClient(httpClient: httpClient, token: "access-token-secret")

        let environment = try await client.getDefaultEnvironment()

        XCTAssertEqual(environment.name, "users/me/environments/default")
        XCTAssertEqual(environment.state, .running)
        XCTAssertEqual(environment.sshUsername, "cloud-user")
        XCTAssertEqual(environment.sshHost, "ssh.cloudshell.dev")
        XCTAssertEqual(environment.sshPort, 6000)

        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/users/me/environments/default")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token-secret")
    }

    func testStartDefaultEnvironmentPostsEmptyJSONObjectAndDecodesOperationByDefault() async throws {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: "{\"name\":\"operations/start-op\",\"done\":false}")
        ])
        let client = makeClient(httpClient: httpClient)

        let operation = try await client.startDefaultEnvironment()

        XCTAssertEqual(operation, CloudShellOperation(name: "operations/start-op", done: false))

        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/users/me/environments/default:start")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{}")
    }

    func testStartDefaultEnvironmentCanSendAccessTokenAndPublicKeys() async throws {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: "{\"name\":\"operations/start-op\",\"done\":false}")
        ])
        let client = makeClient(httpClient: httpClient)

        _ = try await client.startDefaultEnvironment(
            accessToken: "environment-access-token",
            publicKeys: ["ssh-public-key"]
        )

        let request = try XCTUnwrap(httpClient.requests.first)
        let json = try decodeJSONObject(from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(json["accessToken"] as? String, "environment-access-token")
        XCTAssertEqual(json["publicKeys"] as? [String], ["ssh-public-key"])
    }

    func testAddPublicKeyPostsKeyAndDecodesOperation() async throws {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: "{\"name\":\"operations/add-key\",\"done\":true}")
        ])
        let client = makeClient(httpClient: httpClient)

        let operation = try await client.addPublicKey("ssh-public-key")

        XCTAssertEqual(operation, CloudShellOperation(name: "operations/add-key", done: true))

        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/users/me/environments/default:addPublicKey")
        let json = try decodeJSONObject(from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(json["key"] as? String, "ssh-public-key")
    }

    func testAuthorizeDefaultEnvironmentPostsCredentialPayloadAndDecodesOperation() async throws {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: "{\"name\":\"operations/authorize\",\"done\":true}")
        ])
        let client = makeClient(httpClient: httpClient)
        let session = AuthSession(
            accessToken: "environment-access-token",
            refreshToken: "refresh-token",
            idToken: "environment-id-token",
            expiresAt: cloudShellAPITestDate("2026-05-16T12:00:00Z")
        )

        let operation = try await client.authorizeDefaultEnvironment(with: session)

        XCTAssertEqual(operation, CloudShellOperation(name: "operations/authorize", done: true))

        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/users/me/environments/default:authorize")
        let json = try decodeJSONObject(from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(json["accessToken"] as? String, "environment-access-token")
        XCTAssertEqual(json["idToken"] as? String, "environment-id-token")
        XCTAssertEqual(json["expireTime"] as? String, "2026-05-16T12:00:00Z")
    }

    func testFetchOperationEncodesNamePathSafelyAndDecodesOperation() async throws {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: "{\"name\":\"operations/cloud shell/op?with#fragment\",\"done\":true}")
        ])
        let client = makeClient(httpClient: httpClient)

        let operation = try await client.fetchOperation(named: "operations/cloud shell/op?with#fragment")

        XCTAssertEqual(operation, CloudShellOperation(name: "operations/cloud shell/op?with#fragment", done: true))

        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.percentEncodedPath, "/operations/cloud%20shell/op%3Fwith%23fragment")
        XCTAssertNil(request.url?.query)
    }

    func testMapsHTTPStatusErrors() async {
        await assertThrowsCloudShellClientError(.unauthorized) {
            try await self.makeFailingClient(statusCode: 401, message: "expired token").getDefaultEnvironment()
        }
        await assertThrowsCloudShellClientError(.forbidden(message: "permission denied")) {
            try await self.makeFailingClient(statusCode: 403, message: "permission denied").getDefaultEnvironment()
        }
        await assertThrowsCloudShellClientError(.quotaExceeded(message: "quota exhausted")) {
            try await self.makeFailingClient(statusCode: 429, message: "quota exhausted").getDefaultEnvironment()
        }
        await assertThrowsCloudShellClientError(.unavailable(message: "try later")) {
            try await self.makeFailingClient(statusCode: 503, message: "try later").getDefaultEnvironment()
        }
        await assertThrowsCloudShellClientError(.unexpectedStatus(code: 500, message: "boom")) {
            try await self.makeFailingClient(statusCode: 500, message: "boom").getDefaultEnvironment()
        }
    }

    func testMalformedSuccessJSONMapsToInvalidResponse() async {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 200, body: "{\"name\":\"users/me/environments/default\",\"state\":\"RUNNING\"")
        ])
        let client = makeClient(httpClient: httpClient)

        await assertThrowsCloudShellClientError(.invalidResponse) {
            try await client.getDefaultEnvironment()
        }
    }

    func testErrorMessagesAreRedactedBeforeMapping() async {
        let httpClient = RecordingHTTPClient(responses: [
            .json(statusCode: 500, body: "{\"error\":{\"message\":\"request failed for Bearer raw-access-token and refreshToken=raw-refresh-token\"}}")
        ])
        let client = makeClient(httpClient: httpClient)

        do {
            _ = try await client.getDefaultEnvironment()
            XCTFail("Expected request to throw")
        } catch let error as CloudShellError {
            guard case .unexpectedStatus(_, let message) = error else {
                return XCTFail("Expected unexpectedStatus, got \(error)")
            }
            XCTAssertFalse(message?.contains("raw-access-token") ?? true)
            XCTAssertFalse(message?.contains("raw-refresh-token") ?? true)
            XCTAssertTrue(message?.contains("<redacted>") ?? false)
        } catch {
            XCTFail("Expected CloudShellError, got \(error)")
        }
    }

    private func makeFailingClient(statusCode: Int, message: String) -> CloudShellAPIClient {
        let body = "{\"error\":{\"message\":\"\(message)\"}}"
        let httpClient = RecordingHTTPClient(responses: [.json(statusCode: statusCode, body: body)])
        return makeClient(httpClient: httpClient)
    }
}

private func makeClient(httpClient: RecordingHTTPClient, token: String = "access-token") -> CloudShellAPIClient {
    CloudShellAPIClient(
        baseURL: URL(string: "https://cloudshell.example")!,
        httpClient: httpClient,
        accessTokenProvider: { token }
    )
}

private func assertThrowsCloudShellClientError<T>(
    _ expected: CloudShellError,
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected CloudShellError.\(expected)", file: file, line: line)
    } catch let error as CloudShellError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected CloudShellError.\(expected), got \(error)", file: file, line: line)
    }
}

private func decodeJSONObject(from data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func cloudShellAPITestDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value)!
}

private final class RecordingHTTPClient: HTTPClient {
    struct StubbedResponse {
        let statusCode: Int
        let body: Data

        static func json(statusCode: Int, body: String) -> StubbedResponse {
            StubbedResponse(statusCode: statusCode, body: Data(body.utf8))
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [StubbedResponse]

    init(responses: [StubbedResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response.body, httpResponse)
    }
}
