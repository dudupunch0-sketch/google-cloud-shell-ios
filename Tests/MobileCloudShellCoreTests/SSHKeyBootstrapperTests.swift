import XCTest
@testable import MobileCloudShellCore

final class SSHKeyBootstrapperTests: XCTestCase {
    func testRegistersNewlyCreatedPublicKeyAndWaitsForOperation() async throws {
        let keyPair = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "new")
        let store = BootstrapKeyPairStore(keyPair: nil)
        let generator = BootstrapKeyGenerator(keyPair: keyPair)
        let keyManager = SSHKeyManager(store: store, generator: generator)
        let registrar = RecordingPublicKeyRegistrar(
            operation: CloudShellOperation(name: "operations/add-key", done: false)
        )
        let poller = RecordingBootstrapOperationPoller(
            completedOperation: CloudShellOperation(name: "operations/add-key", done: true)
        )
        let bootstrapper = SSHKeyBootstrapper(
            keyManager: keyManager,
            registrar: registrar,
            operationPoller: poller
        )

        let result = try await bootstrapper.bootstrapKeyPair(preferredAlgorithm: .ecdsaP256)

        XCTAssertEqual(result.keyPair, keyPair)
        XCTAssertTrue(result.wasCreated)
        XCTAssertEqual(result.registrationOperation, CloudShellOperation(name: "operations/add-key", done: true))
        XCTAssertEqual(registrar.registeredKeys, [keyPair.publicKey.rawValue])
        XCTAssertEqual(poller.operations, [CloudShellOperation(name: "operations/add-key", done: false)])
    }

    func testSkipsRegistrationForExistingKeyByDefault() async throws {
        let existing = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "existing")
        let generated = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "generated")
        let store = BootstrapKeyPairStore(keyPair: existing)
        let generator = BootstrapKeyGenerator(keyPair: generated)
        let keyManager = SSHKeyManager(store: store, generator: generator)
        let registrar = RecordingPublicKeyRegistrar(
            operation: CloudShellOperation(name: "operations/add-key", done: false)
        )
        let poller = RecordingBootstrapOperationPoller(
            completedOperation: CloudShellOperation(name: "operations/add-key", done: true)
        )
        let bootstrapper = SSHKeyBootstrapper(
            keyManager: keyManager,
            registrar: registrar,
            operationPoller: poller
        )

        let result = try await bootstrapper.bootstrapKeyPair(preferredAlgorithm: .ecdsaP256)

        XCTAssertEqual(result.keyPair, existing)
        XCTAssertFalse(result.wasCreated)
        XCTAssertNil(result.registrationOperation)
        XCTAssertEqual(registrar.registeredKeys, [])
        XCTAssertEqual(poller.operations, [])
        XCTAssertEqual(generator.requestedAlgorithms, [])
    }

    func testCanRegisterExistingKeyWhenExplicitlyRequested() async throws {
        let existing = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "existing")
        let store = BootstrapKeyPairStore(keyPair: existing)
        let keyManager = SSHKeyManager(store: store, generator: BootstrapKeyGenerator(keyPair: existing))
        let registrar = RecordingPublicKeyRegistrar(
            operation: CloudShellOperation(name: "operations/add-key", done: true)
        )
        let poller = RecordingBootstrapOperationPoller(
            completedOperation: CloudShellOperation(name: "operations/add-key", done: true)
        )
        let bootstrapper = SSHKeyBootstrapper(
            keyManager: keyManager,
            registrar: registrar,
            operationPoller: poller
        )

        let result = try await bootstrapper.bootstrapKeyPair(registerExistingKey: true)

        XCTAssertFalse(result.wasCreated)
        XCTAssertEqual(registrar.registeredKeys, [existing.publicKey.rawValue])
        XCTAssertEqual(poller.operations, [CloudShellOperation(name: "operations/add-key", done: true)])
    }

    func testRollsBackNewlyCreatedKeyWhenRegistrationFails() async throws {
        let keyPair = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "new")
        let store = BootstrapKeyPairStore(keyPair: nil)
        let keyManager = SSHKeyManager(store: store, generator: BootstrapKeyGenerator(keyPair: keyPair))
        let registrar = RecordingPublicKeyRegistrar(
            operation: CloudShellOperation(name: "operations/add-key", done: false),
            error: BootstrapFailure.registrationFailed
        )
        let bootstrapper = SSHKeyBootstrapper(
            keyManager: keyManager,
            registrar: registrar,
            operationPoller: RecordingBootstrapOperationPoller(
                completedOperation: CloudShellOperation(name: "operations/add-key", done: true)
            )
        )

        do {
            _ = try await bootstrapper.bootstrapKeyPair()
            XCTFail("Expected registration failure")
        } catch let error as BootstrapFailure {
            XCTAssertEqual(error, .registrationFailed)
        } catch {
            XCTFail("Expected BootstrapFailure, got \(error)")
        }
        XCTAssertNil(try await store.loadKeyPair())
        XCTAssertEqual(store.deleteCount, 1)
    }

    func testRollsBackNewlyCreatedKeyWhenOperationPollingFails() async throws {
        let keyPair = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "new")
        let store = BootstrapKeyPairStore(keyPair: nil)
        let keyManager = SSHKeyManager(store: store, generator: BootstrapKeyGenerator(keyPair: keyPair))
        let registrar = RecordingPublicKeyRegistrar(
            operation: CloudShellOperation(name: "operations/add-key", done: false)
        )
        let poller = RecordingBootstrapOperationPoller(
            completedOperation: CloudShellOperation(name: "operations/add-key", done: true),
            error: BootstrapFailure.pollingFailed
        )
        let bootstrapper = SSHKeyBootstrapper(
            keyManager: keyManager,
            registrar: registrar,
            operationPoller: poller
        )

        do {
            _ = try await bootstrapper.bootstrapKeyPair()
            XCTFail("Expected polling failure")
        } catch let error as BootstrapFailure {
            XCTAssertEqual(error, .pollingFailed)
        } catch {
            XCTFail("Expected BootstrapFailure, got \(error)")
        }
        XCTAssertNil(try await store.loadKeyPair())
        XCTAssertEqual(store.deleteCount, 1)
    }

    func testReportsRollbackFailureInsteadOfSilentlyLeavingUnregisteredKey() async throws {
        let keyPair = try makeBootstrapKeyPair(algorithm: .ecdsaP256, comment: "new")
        let store = BootstrapKeyPairStore(keyPair: nil, deleteError: BootstrapFailure.rollbackFailed)
        let keyManager = SSHKeyManager(store: store, generator: BootstrapKeyGenerator(keyPair: keyPair))
        let registrar = RecordingPublicKeyRegistrar(
            operation: CloudShellOperation(name: "operations/add-key", done: false),
            error: BootstrapFailure.registrationFailed
        )
        let bootstrapper = SSHKeyBootstrapper(
            keyManager: keyManager,
            registrar: registrar,
            operationPoller: RecordingBootstrapOperationPoller(
                completedOperation: CloudShellOperation(name: "operations/add-key", done: true)
            )
        )

        do {
            _ = try await bootstrapper.bootstrapKeyPair()
            XCTFail("Expected rollback failure")
        } catch let error as SSHKeyBootstrapError {
            XCTAssertEqual(
                error,
                .rollbackFailed(
                    originalErrorDescription: "registrationFailed",
                    rollbackErrorDescription: "rollbackFailed"
                )
            )
        } catch {
            XCTFail("Expected SSHKeyBootstrapError, got \(error)")
        }
        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertEqual(try await store.loadKeyPair(), keyPair)
    }
}

private enum BootstrapFailure: Error, Equatable {
    case registrationFailed
    case pollingFailed
    case rollbackFailed
}

private final class BootstrapKeyPairStore: SSHKeyPairStore {
    private(set) var deleteCount = 0
    private var keyPair: SSHKeyPair?
    private let deleteError: Error?

    init(keyPair: SSHKeyPair?, deleteError: Error? = nil) {
        self.keyPair = keyPair
        self.deleteError = deleteError
    }

    func loadKeyPair() async throws -> SSHKeyPair? {
        keyPair
    }

    func saveKeyPair(_ keyPair: SSHKeyPair) async throws {
        self.keyPair = keyPair
    }

    func deleteKeyPair() async throws {
        deleteCount += 1
        if let deleteError { throw deleteError }
        keyPair = nil
    }
}

private final class BootstrapKeyGenerator: SSHKeyGenerating {
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

private final class RecordingPublicKeyRegistrar: CloudShellPublicKeyRegistering {
    private(set) var registeredKeys: [String] = []
    private let operation: CloudShellOperation
    private let error: Error?

    init(operation: CloudShellOperation, error: Error? = nil) {
        self.operation = operation
        self.error = error
    }

    func addPublicKey(_ key: String) async throws -> CloudShellOperation {
        registeredKeys.append(key)
        if let error { throw error }
        return operation
    }
}

private final class RecordingBootstrapOperationPoller: CloudShellOperationPolling {
    private(set) var operations: [CloudShellOperation] = []
    private let completedOperation: CloudShellOperation
    private let error: Error?

    init(completedOperation: CloudShellOperation, error: Error? = nil) {
        self.completedOperation = completedOperation
        self.error = error
    }

    func waitUntilDone(_ operation: CloudShellOperation) async throws -> CloudShellOperation {
        operations.append(operation)
        if let error { throw error }
        return completedOperation
    }
}

private func makeBootstrapKeyPair(algorithm: SSHKeyAlgorithm, comment: String) throws -> SSHKeyPair {
    let publicKey = try OpenSSHPublicKey(rawValue: "\(algorithm.rawValue) \(validBootstrapPublicKeyBlob(for: algorithm)) \(comment)")
    let privateKey = try SSHPrivateKeyMaterial(pemString: bootstrapPrivateKeyPEM)
    return SSHKeyPair(publicKey: publicKey, privateKey: privateKey)
}

private func validBootstrapPublicKeyBlob(for algorithm: SSHKeyAlgorithm) -> String {
    switch algorithm {
    case .ecdsaP256:
        return "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A="
    case .ed25519:
        return "AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"
    case .rsa:
        return "AAAAB3NzaC1yc2EAAAADAQABAAAAQQABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9A"
    }
}

private let bootstrapPrivateKeyPEM = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAcHJpdmF0ZS1rZXktbWF0ZXJpYWw=
-----END OPENSSH PRIVATE KEY-----
"""
