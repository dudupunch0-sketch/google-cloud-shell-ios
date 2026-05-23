#if canImport(Security)
import Foundation
import XCTest
@testable import MobileCloudShellCore

final class KeychainSSHKeyPairStoreTests: XCTestCase {
    func testLoadReturnsNilWhenKeychainItemIsMissing() async throws {
        let keychain = FakeKeychainAccessor()
        let store = makeStore(keychain: keychain)

        let keyPair = try await store.loadKeyPair()

        XCTAssertNil(keyPair)
        XCTAssertEqual(keychain.operations, [.copy(service: testService, account: testAccount)])
    }

    func testLoadDecodesStoredKeyPair() async throws {
        let expected = try makeKeyPair(comment: "stored")
        let keychain = FakeKeychainAccessor()
        keychain.storedData = try encodedKeyPair(expected)
        let store = makeStore(keychain: keychain)

        let loaded = try await store.loadKeyPair()

        XCTAssertEqual(loaded, expected)
        XCTAssertEqual(keychain.operations, [.copy(service: testService, account: testAccount)])
    }

    func testLoadRejectsMalformedStoredKeyPairWithoutLeakingRawData() async {
        let keychain = FakeKeychainAccessor()
        let malformedSecretPayload = "not-json-private-key-material"
        keychain.storedData = Data(malformedSecretPayload.utf8)
        let store = makeStore(keychain: keychain)

        await assertThrowsKeychainStoreError(.invalidStoredKeyPair, sensitiveFragments: [malformedSecretPayload]) {
            try await store.loadKeyPair()
        }
    }

    func testLoadRejectsInvalidStoredFieldsWithoutLeakingRawData() async throws {
        let invalidPrivateKey = "-----BEGIN OPENSSH PRIVATE KEY-----\nsecret-invalid-material\n-----END OPENSSH PRIVATE KEY-----"
        let keychain = FakeKeychainAccessor()
        keychain.storedData = try encodedEnvelope(publicKey: "not-a-valid-public-key", privateKeyPEM: invalidPrivateKey)
        let store = makeStore(keychain: keychain)

        await assertThrowsKeychainStoreError(.invalidStoredKeyPair, sensitiveFragments: [invalidPrivateKey]) {
            try await store.loadKeyPair()
        }
    }

    func testLoadRejectsEmptyServiceBeforeTouchingKeychain() async {
        let keychain = FakeKeychainAccessor()
        let store = makeStore(
            keychain: keychain,
            configuration: KeychainSSHKeyPairStoreConfiguration(service: " \n\t", account: testAccount)
        )

        await assertThrowsKeychainStoreError(.invalidConfiguration(field: .service)) {
            try await store.loadKeyPair()
        }
        XCTAssertEqual(keychain.operations, [])
    }

    func testSaveRejectsEmptyAccountBeforeTouchingKeychain() async throws {
        let keychain = FakeKeychainAccessor()
        let store = makeStore(
            keychain: keychain,
            configuration: KeychainSSHKeyPairStoreConfiguration(service: testService, account: "")
        )

        await assertThrowsKeychainStoreError(.invalidConfiguration(field: .account)) {
            try await store.saveKeyPair(makeKeyPair(comment: "invalid-account"))
        }
        XCTAssertEqual(keychain.operations, [])
    }

    func testSaveAddsJSONEnvelopeWithDeviceOnlyAccessibility() async throws {
        let keyPair = try makeKeyPair(comment: "saved")
        let keychain = FakeKeychainAccessor()
        let store = makeStore(keychain: keychain)

        try await store.saveKeyPair(keyPair)

        XCTAssertEqual(keychain.addedItems.count, 1)
        let added = try XCTUnwrap(keychain.addedItems.first)
        XCTAssertEqual(added.service, testService)
        XCTAssertEqual(added.account, testAccount)
        XCTAssertEqual(added.accessibility, .whenUnlockedThisDeviceOnly)
        XCTAssertEqual(try decodedEnvelope(from: added.data).publicKey, keyPair.publicKey.rawValue)
        XCTAssertTrue(
            try decodedEnvelope(from: added.data).privateKeyPEM == keyPair.privateKey.pemString,
            "stored private key PEM should round-trip without printing PEM contents"
        )
        XCTAssertEqual(keychain.operations, [.add(service: testService, account: testAccount)])
    }

    func testSaveUpdatesExistingItemWhenAddFindsDuplicate() async throws {
        let keyPair = try makeKeyPair(comment: "updated")
        let keychain = FakeKeychainAccessor()
        keychain.addStatus = .duplicateItem
        let store = makeStore(keychain: keychain)

        try await store.saveKeyPair(keyPair)

        XCTAssertEqual(keychain.addedItems.count, 1)
        XCTAssertEqual(keychain.updatedItems.count, 1)
        let updated = try XCTUnwrap(keychain.updatedItems.first)
        XCTAssertEqual(updated.service, testService)
        XCTAssertEqual(updated.account, testAccount)
        XCTAssertEqual(updated.accessibility, .whenUnlockedThisDeviceOnly)
        XCTAssertEqual(try decodedEnvelope(from: updated.data).publicKey, keyPair.publicKey.rawValue)
        XCTAssertTrue(
            try decodedEnvelope(from: updated.data).privateKeyPEM == keyPair.privateKey.pemString,
            "stored private key PEM should round-trip without printing PEM contents"
        )
        XCTAssertEqual(keychain.operations, [
            .add(service: testService, account: testAccount),
            .update(service: testService, account: testAccount)
        ])
    }

    func testSaveUsesConfiguredAccessibility() async throws {
        let keyPair = try makeKeyPair(comment: "after-first-unlock")
        let keychain = FakeKeychainAccessor()
        let store = makeStore(
            keychain: keychain,
            configuration: KeychainSSHKeyPairStoreConfiguration(
                service: testService,
                account: testAccount,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        )

        try await store.saveKeyPair(keyPair)

        XCTAssertEqual(keychain.addedItems.first?.accessibility, .afterFirstUnlockThisDeviceOnly)
    }

    func testSaveReportsAddFailureWithoutLeakingPrivateKey() async throws {
        let keyPair = try makeKeyPair(comment: "add-failure")
        let keychain = FakeKeychainAccessor()
        keychain.addStatus = .failure(-25291)
        let store = makeStore(keychain: keychain)

        await assertThrowsKeychainStoreError(.unexpectedStatus(operation: .save, status: -25291)) {
            try await store.saveKeyPair(keyPair)
        }
        XCTAssertEqual(keychain.operations, [.add(service: testService, account: testAccount)])
    }

    func testSaveReportsUpdateFailureWithoutLeakingPrivateKey() async throws {
        let keyPair = try makeKeyPair(comment: "update-failure")
        let keychain = FakeKeychainAccessor()
        keychain.addStatus = .duplicateItem
        keychain.updateStatus = .failure(-25308)
        let store = makeStore(keychain: keychain)

        await assertThrowsKeychainStoreError(.unexpectedStatus(operation: .update, status: -25308)) {
            try await store.saveKeyPair(keyPair)
        }
        XCTAssertEqual(keychain.operations, [
            .add(service: testService, account: testAccount),
            .update(service: testService, account: testAccount)
        ])
    }

    func testDeleteTreatsMissingItemAsSuccess() async throws {
        let keychain = FakeKeychainAccessor()
        keychain.deleteStatus = .itemNotFound
        let store = makeStore(keychain: keychain)

        try await store.deleteKeyPair()

        XCTAssertEqual(keychain.operations, [.delete(service: testService, account: testAccount)])
    }

    func testDeleteReportsFailure() async {
        let keychain = FakeKeychainAccessor()
        keychain.deleteStatus = .failure(-25293)
        let store = makeStore(keychain: keychain)

        await assertThrowsKeychainStoreError(.unexpectedStatus(operation: .delete, status: -25293)) {
            try await store.deleteKeyPair()
        }
        XCTAssertEqual(keychain.operations, [.delete(service: testService, account: testAccount)])
    }

    func testUnexpectedStatusIsOperationOnlyAndRedacted() async {
        let keychain = FakeKeychainAccessor()
        keychain.copyResult = .failure(-34018)
        let store = makeStore(keychain: keychain)

        await assertThrowsKeychainStoreError(.unexpectedStatus(operation: .load, status: -34018)) {
            try await store.loadKeyPair()
        }
    }
}

private let testService = "com.example.mobile-cloud-shell.test.ssh-key"
private let testAccount = "primary"

private func makeStore(
    keychain: FakeKeychainAccessor,
    configuration: KeychainSSHKeyPairStoreConfiguration = KeychainSSHKeyPairStoreConfiguration(
        service: testService,
        account: testAccount
    )
) -> KeychainSSHKeyPairStore {
    KeychainSSHKeyPairStore(
        configuration: configuration,
        keychain: keychain
    )
}

private final class FakeKeychainAccessor: KeychainAccessing {
    var copyResult: KeychainLookupResult?
    var addStatus: KeychainOperationStatus = .success
    var updateStatus: KeychainOperationStatus = .success
    var deleteStatus: KeychainOperationStatus = .success
    var storedData: Data?
    private(set) var addedItems: [KeychainGenericPasswordItem] = []
    private(set) var updatedItems: [KeychainGenericPasswordItem] = []
    private(set) var operations: [KeychainOperation] = []

    func copyGenericPassword(service: String, account: String) -> KeychainLookupResult {
        operations.append(.copy(service: service, account: account))
        if let copyResult {
            return copyResult
        }
        if let storedData {
            return .found(storedData)
        }
        return .notFound
    }

    func addGenericPassword(_ item: KeychainGenericPasswordItem) -> KeychainOperationStatus {
        operations.append(.add(service: item.service, account: item.account))
        addedItems.append(item)
        return addStatus
    }

    func updateGenericPassword(_ item: KeychainGenericPasswordItem) -> KeychainOperationStatus {
        operations.append(.update(service: item.service, account: item.account))
        updatedItems.append(item)
        return updateStatus
    }

    func deleteGenericPassword(service: String, account: String) -> KeychainOperationStatus {
        operations.append(.delete(service: service, account: account))
        return deleteStatus
    }
}

private enum KeychainOperation: Equatable {
    case copy(service: String, account: String)
    case add(service: String, account: String)
    case update(service: String, account: String)
    case delete(service: String, account: String)
}

private struct StoredKeyEnvelope: Decodable {
    let publicKey: String
    let privateKeyPEM: String
}

private func encodedKeyPair(_ keyPair: SSHKeyPair) throws -> Data {
    try encodedEnvelope(publicKey: keyPair.publicKey.rawValue, privateKeyPEM: keyPair.privateKey.pemString)
}

private func encodedEnvelope(publicKey: String, privateKeyPEM: String) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "publicKey": publicKey,
            "privateKeyPEM": privateKeyPEM
        ],
        options: [.sortedKeys]
    )
}

private func decodedEnvelope(from data: Data) throws -> StoredKeyEnvelope {
    try JSONDecoder().decode(StoredKeyEnvelope.self, from: data)
}

private func makeKeyPair(comment: String = "ios") throws -> SSHKeyPair {
    let publicKey = try OpenSSHPublicKey(
        rawValue: "ecdsa-sha2-nistp256 \(validECDSAPublicKeyBlob) \(comment)"
    )
    let privateKey = try SSHPrivateKeyMaterial(pemString: validPrivateKeyPEM)
    return SSHKeyPair(publicKey: publicKey, privateKey: privateKey)
}

private let validECDSAPublicKeyBlob = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A="

private let validPrivateKeyPEM = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAcHJpdmF0ZS1rZXktbWF0ZXJpYWw=
-----END OPENSSH PRIVATE KEY-----
"""

private func assertThrowsKeychainStoreError<T>(
    _ expected: KeychainSSHKeyPairStoreError,
    sensitiveFragments: [String] = [],
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected KeychainSSHKeyPairStoreError.\(expected)", file: file, line: line)
    } catch let error as KeychainSSHKeyPairStoreError {
        XCTAssertEqual(error, expected, file: file, line: line)
        for fragment in [validPrivateKeyPEM] + sensitiveFragments {
            XCTAssertFalse(String(describing: error).contains(fragment), file: file, line: line)
            XCTAssertFalse(error.localizedDescription.contains(fragment), file: file, line: line)
        }
    } catch {
        XCTFail("Expected KeychainSSHKeyPairStoreError.\(expected), got \(error)", file: file, line: line)
    }
}
#endif
