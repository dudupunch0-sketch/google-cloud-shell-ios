import XCTest
@testable import MobileCloudShellCore

final class RedactedLoggerTests: XCTestCase {
    func testRedactsAuthorizationBearerTokens() {
        let rawToken = "ya29.raw-access-token.secret"
        let message = "Authorization: Bearer \(rawToken)"

        let redacted = RedactedLogger.redact(message)

        XCTAssertFalse(redacted.contains(rawToken))
        XCTAssertTrue(redacted.contains("Authorization: Bearer <redacted>"))
    }

    func testRedactsOAuthTokenFields() {
        let accessToken = "raw-access-token"
        let idToken = "raw-id-token"
        let refreshToken = "raw-refresh-token"
        let message = """
        {
          "access_token": "\(accessToken)",
          "id_token": "\(idToken)",
          "refresh_token": "\(refreshToken)",
          "accessToken": "\(accessToken)",
          "idToken": "\(idToken)",
          "refreshToken": "\(refreshToken)"
        }
        access_token=\(accessToken)&refreshToken=\(refreshToken)
        """

        let redacted = RedactedLogger.redact(message)

        XCTAssertFalse(redacted.contains(accessToken))
        XCTAssertFalse(redacted.contains(idToken))
        XCTAssertFalse(redacted.contains(refreshToken))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testRedactsPEMPrivateKeyBlocks() {
        let privateKeyBody = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwsecretPrivateKeyMaterial"
        let message = """
        before
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(privateKeyBody)
        -----END OPENSSH PRIVATE KEY-----
        after
        """

        let redacted = RedactedLogger.redact(message)

        XCTAssertFalse(redacted.contains(privateKeyBody))
        XCTAssertTrue(redacted.contains("-----BEGIN PRIVATE KEY-----"))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertTrue(redacted.contains("-----END PRIVATE KEY-----"))
    }

    func testLoggerSinkReceivesRedactedMessageOnly() {
        let rawToken = "raw-access-token"
        var messages: [String] = []
        let logger = RedactedLogger(sink: { messages.append($0) })

        logger.log("Bearer \(rawToken)")

        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(messages[0].contains(rawToken))
        XCTAssertEqual(messages[0], "Bearer <redacted>")
    }
}
