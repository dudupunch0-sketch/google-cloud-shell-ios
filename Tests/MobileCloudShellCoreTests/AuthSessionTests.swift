import Foundation
import XCTest
@testable import MobileCloudShellCore

final class AuthSessionTests: XCTestCase {
    func testAuthorizationHeaderUsesBearerToken() {
        let session = AuthSession(
            accessToken: "access-token-123",
            refreshToken: "refresh-token-456",
            idToken: "id-token-789",
            expiresAt: authSessionTestDate("2026-05-16T12:00:00Z")
        )

        XCTAssertEqual(session.authorizationHeader, "Bearer access-token-123")
    }

    func testIsExpiredTreatsExpiryWithinLeewayAsExpired() {
        let now = authSessionTestDate("2026-05-16T12:00:00Z")
        let expiresWithinLeeway = AuthSession(
            accessToken: "access-token",
            refreshToken: nil,
            idToken: nil,
            expiresAt: now.addingTimeInterval(30)
        )
        let expiresAfterLeeway = AuthSession(
            accessToken: "access-token",
            refreshToken: nil,
            idToken: nil,
            expiresAt: now.addingTimeInterval(61)
        )

        XCTAssertTrue(expiresWithinLeeway.isExpired(at: now, leeway: 60))
        XCTAssertFalse(expiresAfterLeeway.isExpired(at: now, leeway: 60))
    }

    func testAuthSessionStoreSavesLoadsAndDeletesThroughInjectedCodableStorage() throws {
        let storage = InMemoryAuthSessionCodableStorage()
        let store = AuthSessionStore(storage: storage, key: "test.auth.session")
        let session = AuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: "id-token",
            expiresAt: authSessionTestDate("2026-05-16T12:00:00Z")
        )

        XCTAssertNil(try store.load())

        try store.save(session)
        XCTAssertEqual(try store.load(), session)

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testOAuthClientProtocolCanBeSatisfiedByInjectedFake() async throws {
        let expected = AuthSession(
            accessToken: "fake-access-token",
            refreshToken: "fake-refresh-token",
            idToken: "fake-id-token",
            expiresAt: authSessionTestDate("2026-05-16T12:00:00Z")
        )
        let client: any OAuthClient = FakeOAuthClient(session: expected)

        let signedIn = try await client.signIn()
        let refreshed = try await client.refreshSession(signedIn)
        try await client.signOut()

        XCTAssertEqual(signedIn, expected)
        XCTAssertEqual(refreshed, expected)
    }
}

private final class InMemoryAuthSessionCodableStorage: AuthSessionCodableStorage {
    private var values: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
        guard let data = values[key] else { return nil }
        return try decoder.decode(type, from: data)
    }

    func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        values[key] = try encoder.encode(value)
    }

    func delete(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}

private struct FakeOAuthClient: OAuthClient {
    let session: AuthSession

    func signIn() async throws -> AuthSession {
        session
    }

    func refreshSession(_ session: AuthSession) async throws -> AuthSession {
        self.session
    }

    func signOut() async throws {}
}

private func authSessionTestDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value)!
}
