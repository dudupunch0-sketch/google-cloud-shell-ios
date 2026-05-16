import XCTest
@testable import MobileCloudShellCore

final class SSHPrivateKeyMaterialTests: XCTestCase {
    private let privateKeyBody = "b3BlbnNzaC1rZXktdjEAcHJpdmF0ZS1rZXktbWF0ZXJpYWw="

    private var privateKeyPEM: String {
        """
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(privateKeyBody)
        -----END OPENSSH PRIVATE KEY-----
        """
    }

    func testAcceptsPEMLookingPrivateKey() throws {
        let material = try SSHPrivateKeyMaterial(pemString: privateKeyPEM)

        XCTAssertEqual(material.pemString, privateKeyPEM)
    }

    func testRedactsDescriptionDebugAndLoggerOutput() throws {
        let material = try SSHPrivateKeyMaterial(pemString: privateKeyPEM)

        let description = String(describing: material)
        let debugDescription = String(reflecting: material)
        var logMessages: [String] = []
        let logger = RedactedLogger(sink: { logMessages.append($0) })
        logger.log("loaded \(material)")

        XCTAssertFalse(description.contains(privateKeyBody))
        XCTAssertFalse(debugDescription.contains(privateKeyBody))
        XCTAssertFalse(logMessages.joined().contains(privateKeyBody))
        XCTAssertTrue(description.contains("<redacted>"))
        XCTAssertTrue(debugDescription.contains("<redacted>"))
        XCTAssertTrue(logMessages.joined().contains("<redacted>"))
    }

    func testRawPEMIsStillRedactedByLogger() throws {
        let material = try SSHPrivateKeyMaterial(pemString: privateKeyPEM)

        let redacted = RedactedLogger.redact("raw=\(material.pemString)")

        XCTAssertFalse(redacted.contains(privateKeyBody))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testRejectsMalformedPEM() {
        assertThrowsSSHKeyError(.invalidPrivateKeyMaterial) {
            try SSHPrivateKeyMaterial(
                pemString: """
                -----BEGIN OPENSSH PRIVATE KEY-----
                \(privateKeyBody)
                """
            )
        }
        assertThrowsSSHKeyError(.invalidPrivateKeyMaterial) {
            try SSHPrivateKeyMaterial(
                pemString: """
                -----BEGIN OPENSSH PRIVATE KEY-----
                not base 64
                -----END OPENSSH PRIVATE KEY-----
                """
            )
        }
        assertThrowsSSHKeyError(.invalidPrivateKeyMaterial) {
            try SSHPrivateKeyMaterial(
                pemString: """
                -----BEGIN OPENSSH PRIVATE KEY-----
                \(privateKeyBody)
                -----END RSA PRIVATE KEY-----
                """
            )
        }
    }

    func testRejectsOpenSSHPrivateKeyWithoutOpenSSHMagic() {
        assertThrowsSSHKeyError(.invalidPrivateKeyMaterial) {
            try SSHPrivateKeyMaterial(
                pemString: """
                -----BEGIN OPENSSH PRIVATE KEY-----
                bm90LW9wZW5zc2gtbWFnaWM=
                -----END OPENSSH PRIVATE KEY-----
                """
            )
        }
    }
}

private func assertThrowsSSHKeyError<T>(
    _ expected: SSHKeyError,
    _ expression: () throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        _ = try expression()
        XCTFail("Expected SSHKeyError.\(expected)", file: file, line: line)
    } catch let error as SSHKeyError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected SSHKeyError.\(expected), got \(error)", file: file, line: line)
    }
}
