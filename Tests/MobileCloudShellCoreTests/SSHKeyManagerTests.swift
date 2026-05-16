import XCTest
@testable import MobileCloudShellCore

final class SSHKeyManagerTests: XCTestCase {
    func testLoadsExistingKeyPairWithoutGeneratorOrStoreWrites() async throws {
        let existing = try makeKeyPair(algorithm: .rsa, comment: "existing")
        let store = ManagerKeyPairStore(keyPair: existing)
        let generator = ManagerKeyGenerator(keyPair: try makeKeyPair(algorithm: .ecdsaP256))
        let manager = SSHKeyManager(store: store, generator: generator)

        let resolution = try await manager.resolveKeyPair(preferredAlgorithm: .ecdsaP256)

        XCTAssertEqual(resolution.keyPair, existing)
        XCTAssertFalse(resolution.wasCreated)
        XCTAssertEqual(store.loadCount, 1)
        XCTAssertEqual(store.savedPairs, [])
        XCTAssertEqual(generator.requestedAlgorithms, [])
    }

    func testGeneratesAndStoresWhenMissing() async throws {
        let generated = try makeKeyPair(algorithm: .ecdsaP256, comment: "generated")
        let store = ManagerKeyPairStore(keyPair: nil)
        let generator = ManagerKeyGenerator(keyPair: generated)
        let manager = SSHKeyManager(store: store, generator: generator)

        let resolution = try await manager.resolveKeyPair(preferredAlgorithm: .ecdsaP256)

        XCTAssertEqual(resolution.keyPair, generated)
        XCTAssertTrue(resolution.wasCreated)
        XCTAssertEqual(generator.requestedAlgorithms, [.ecdsaP256])
        XCTAssertEqual(store.savedPairs, [generated])
    }

    func testRejectsGeneratedPublicKeyAlgorithmMismatch() async throws {
        let mismatched = try makeKeyPair(algorithm: .ed25519, comment: "mismatch")
        let store = ManagerKeyPairStore(keyPair: nil)
        let generator = ManagerKeyGenerator(keyPair: mismatched)
        let manager = SSHKeyManager(store: store, generator: generator)

        await assertThrowsSSHKeyError(.algorithmMismatch(expected: .ecdsaP256, actual: .ed25519)) {
            try await manager.resolveKeyPair(preferredAlgorithm: .ecdsaP256)
        }

        XCTAssertEqual(store.savedPairs, [])
    }

    func testLoadOrCreateKeyPairReturnsResolvedPair() async throws {
        let generated = try makeKeyPair(algorithm: .ecdsaP256)
        let store = ManagerKeyPairStore(keyPair: nil)
        let generator = ManagerKeyGenerator(keyPair: generated)
        let manager = SSHKeyManager(store: store, generator: generator)

        let keyPair = try await manager.loadOrCreateKeyPair(preferredAlgorithm: .ecdsaP256)

        XCTAssertEqual(keyPair, generated)
        XCTAssertEqual(store.savedPairs, [generated])
    }

    func testDeleteKeyPairDelegatesToStore() async throws {
        let existing = try makeKeyPair(algorithm: .ecdsaP256)
        let store = ManagerKeyPairStore(keyPair: existing)
        let manager = SSHKeyManager(store: store, generator: ManagerKeyGenerator(keyPair: existing))

        try await manager.deleteKeyPair()

        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertNil(try await store.loadKeyPair())
    }
}

private final class ManagerKeyPairStore: SSHKeyPairStore {
    private(set) var loadCount = 0
    private(set) var deleteCount = 0
    private(set) var savedPairs: [SSHKeyPair] = []
    private var keyPair: SSHKeyPair?

    init(keyPair: SSHKeyPair?) {
        self.keyPair = keyPair
    }

    func loadKeyPair() async throws -> SSHKeyPair? {
        loadCount += 1
        return keyPair
    }

    func saveKeyPair(_ keyPair: SSHKeyPair) async throws {
        savedPairs.append(keyPair)
        self.keyPair = keyPair
    }

    func deleteKeyPair() async throws {
        deleteCount += 1
        keyPair = nil
    }
}

private final class ManagerKeyGenerator: SSHKeyGenerating {
    private(set) var requestedAlgorithms: [SSHKeyAlgorithm] = []
    private let keyPair: SSHKeyPair

    init(keyPair: SSHKeyPair) {
        self.keyPair = keyPair
    }

    func generateKeyPair(algorithm: SSHKeyAlgorithm) async throws -> SSHKeyPair {
        requestedAlgorithms.append(algorithm)
        return keyPair
    }
}

private func makeKeyPair(algorithm: SSHKeyAlgorithm, comment: String = "ios") throws -> SSHKeyPair {
    let publicKey = try OpenSSHPublicKey(rawValue: "\(algorithm.rawValue) \(validPublicKeyBlob(for: algorithm)) \(comment)")
    let privateKey = try SSHPrivateKeyMaterial(pemString: validPrivateKeyPEM)
    return SSHKeyPair(publicKey: publicKey, privateKey: privateKey)
}

private func validPublicKeyBlob(for algorithm: SSHKeyAlgorithm) -> String {
    switch algorithm {
    case .ecdsaP256:
        return "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A="
    case .ed25519:
        return "AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"
    case .rsa:
        return "AAAAB3NzaC1yc2EAAAADAQABAAAAQQABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9A"
    }
}

private let validPrivateKeyPEM = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAcHJpdmF0ZS1rZXktbWF0ZXJpYWw=
-----END OPENSSH PRIVATE KEY-----
"""

private func assertThrowsSSHKeyError<T>(
    _ expected: SSHKeyError,
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected SSHKeyError.\(expected)", file: file, line: line)
    } catch let error as SSHKeyError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected SSHKeyError.\(expected), got \(error)", file: file, line: line)
    }
}
