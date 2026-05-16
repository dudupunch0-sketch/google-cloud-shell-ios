import Foundation
import XCTest
@testable import MobileCloudShellCore

final class CloudShellErrorTests: XCTestCase {
    func testPublicStatusErrorDescriptionsRedactSecretsDefensively() {
        let rawToken = "raw-access-token"
        let errors: [CloudShellError] = [
            .forbidden(message: "forbidden Bearer \(rawToken)"),
            .quotaExceeded(message: "quota accessToken=\(rawToken)"),
            .unavailable(message: "unavailable refreshToken=\(rawToken)"),
            .unexpectedStatus(code: 500, message: "failed idToken=\(rawToken)")
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.contains(rawToken))
            XCTAssertTrue(error.localizedDescription.contains("<redacted>"))
        }
    }

    func testDecodedOperationErrorRedactsMessage() throws {
        let rawToken = "raw-access-token"
        let json = """
        {
          "code": 7,
          "message": "operation failed for Bearer \(rawToken) and accessToken=\(rawToken)",
          "status": "PERMISSION_DENIED"
        }
        """

        let operationError = try JSONDecoder().decode(CloudShellOperationError.self, from: Data(json.utf8))

        XCTAssertFalse(operationError.message?.contains(rawToken) ?? true)
        XCTAssertTrue(operationError.message?.contains("<redacted>") ?? false)
    }
}
