import XCTest
@testable import MobileCloudShellCore

final class OpenSSHPublicKeyTests: XCTestCase {
    private let publicKeyBlob = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A="

    func testAcceptsAndNormalizesECDSAKey() throws {
        let key = try OpenSSHPublicKey(
            rawValue: "  ecdsa-sha2-nistp256   \(publicKeyBlob)\tcloud-shell-ios  "
        )

        XCTAssertEqual(key.algorithm, .ecdsaP256)
        XCTAssertEqual(key.base64Blob, publicKeyBlob)
        XCTAssertEqual(key.comment, "cloud-shell-ios")
        XCTAssertEqual(key.rawValue, "ecdsa-sha2-nistp256 \(publicKeyBlob) cloud-shell-ios")
    }

    func testAcceptsKeyWithoutComment() throws {
        let key = try OpenSSHPublicKey(rawValue: "ecdsa-sha2-nistp256 \(publicKeyBlob)")

        XCTAssertEqual(key.comment, nil)
        XCTAssertEqual(key.rawValue, "ecdsa-sha2-nistp256 \(publicKeyBlob)")
    }

    func testPreservesOptionalCommentWordsWhenNormalizingWhitespace() throws {
        let key = try OpenSSHPublicKey(
            rawValue: "ecdsa-sha2-nistp256 \(publicKeyBlob)  cloud shell ios  "
        )

        XCTAssertEqual(key.comment, "cloud shell ios")
        XCTAssertEqual(key.rawValue, "ecdsa-sha2-nistp256 \(publicKeyBlob) cloud shell ios")
    }

    func testRejectsUnsupportedAlgorithm() {
        assertThrowsSSHKeyError(.unsupportedPublicKeyAlgorithm("ssh-dss")) {
            try OpenSSHPublicKey(rawValue: "ssh-dss \(publicKeyBlob) legacy-key")
        }
    }

    func testRejectsInvalidBase64Blob() {
        assertThrowsSSHKeyError(.invalidPublicKeyBlob) {
            try OpenSSHPublicKey(rawValue: "ecdsa-sha2-nistp256 not-base64!!! cloud-shell-ios")
        }
    }

    func testRejectsBlobWhoseWireAlgorithmDoesNotMatchPrefix() {
        assertThrowsSSHKeyError(.invalidPublicKeyBlob) {
            try OpenSSHPublicKey(rawValue: "ecdsa-sha2-nistp256 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f cloud-shell-ios")
        }
    }

    func testRejectsMissingParts() {
        assertThrowsSSHKeyError(.malformedPublicKey) {
            try OpenSSHPublicKey(rawValue: "ecdsa-sha2-nistp256")
        }
    }

    func testRejectsEmptyAndNewlineKeys() {
        assertThrowsSSHKeyError(.malformedPublicKey) {
            try OpenSSHPublicKey(rawValue: "   ")
        }
        assertThrowsSSHKeyError(.malformedPublicKey) {
            try OpenSSHPublicKey(rawValue: "ecdsa-sha2-nistp256\n\(publicKeyBlob)")
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
