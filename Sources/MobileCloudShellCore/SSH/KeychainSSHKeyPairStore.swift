#if canImport(Security)
import Foundation
import Security

public enum KeychainItemAccessibility: Equatable, Sendable {
    case whenUnlockedThisDeviceOnly
    case afterFirstUnlockThisDeviceOnly

    var securityValue: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

public struct KeychainSSHKeyPairStoreConfiguration: Equatable, Sendable {
    public let service: String
    /// Keychain account should be a stable per-Google-account identifier in the app layer.
    /// The default is only a single-profile fallback until OAuth user identity is wired in.
    public let account: String
    public let accessibility: KeychainItemAccessibility

    public init(
        service: String = "com.google-cloud-shell-ios.ssh-key-pair",
        account: String = "default",
        accessibility: KeychainItemAccessibility = .whenUnlockedThisDeviceOnly
    ) {
        self.service = service
        self.account = account
        self.accessibility = accessibility
    }
}

public enum KeychainSSHKeyPairStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(field: KeychainSSHKeyPairStoreConfigurationField)
    case invalidStoredKeyPair
    case encodingFailed
    case unexpectedStatus(operation: KeychainSSHKeyPairStoreOperation, status: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            return "Keychain SSH key pair store configuration has an empty \(field.rawValue)."
        case .invalidStoredKeyPair:
            return "Stored SSH key pair could not be decoded."
        case .encodingFailed:
            return "SSH key pair could not be encoded for Keychain storage."
        case .unexpectedStatus(let operation, let status):
            return "Keychain operation failed while attempting to \(operation.errorDescription) (status \(status))."
        }
    }
}

public enum KeychainSSHKeyPairStoreConfigurationField: String, Equatable, Sendable {
    case service
    case account
}

public enum KeychainSSHKeyPairStoreOperation: Equatable, Sendable {
    case load
    case save
    case update
    case delete

    fileprivate var errorDescription: String {
        switch self {
        case .load:
            return "load SSH key pair"
        case .save:
            return "save SSH key pair"
        case .update:
            return "update SSH key pair"
        case .delete:
            return "delete SSH key pair"
        }
    }
}

public struct KeychainSSHKeyPairStore: SSHKeyPairStore {
    private let configuration: KeychainSSHKeyPairStoreConfiguration
    private let keychain: any KeychainAccessing

    public init(configuration: KeychainSSHKeyPairStoreConfiguration = KeychainSSHKeyPairStoreConfiguration()) {
        self.init(configuration: configuration, keychain: SystemKeychainAccessor())
    }

    init(configuration: KeychainSSHKeyPairStoreConfiguration, keychain: any KeychainAccessing) {
        self.configuration = configuration
        self.keychain = keychain
    }

    public func loadKeyPair() async throws -> SSHKeyPair? {
        try validateConfiguration()

        switch keychain.copyGenericPassword(service: configuration.service, account: configuration.account) {
        case .found(let data):
            return try decodeKeyPair(from: data)
        case .notFound:
            return nil
        case .failure(let status):
            throw KeychainSSHKeyPairStoreError.unexpectedStatus(operation: .load, status: status)
        }
    }

    public func saveKeyPair(_ keyPair: SSHKeyPair) async throws {
        try validateConfiguration()

        let item = KeychainGenericPasswordItem(
            service: configuration.service,
            account: configuration.account,
            data: try encodeKeyPair(keyPair),
            accessibility: configuration.accessibility
        )

        switch keychain.addGenericPassword(item) {
        case .success:
            return
        case .duplicateItem:
            switch keychain.updateGenericPassword(item) {
            case .success:
                return
            case .duplicateItem:
                throw KeychainSSHKeyPairStoreError.unexpectedStatus(
                    operation: .update,
                    status: KeychainOperationStatus.duplicateItem.rawStatus
                )
            case .itemNotFound:
                throw KeychainSSHKeyPairStoreError.unexpectedStatus(
                    operation: .update,
                    status: KeychainOperationStatus.itemNotFound.rawStatus
                )
            case .failure(let status):
                throw KeychainSSHKeyPairStoreError.unexpectedStatus(operation: .update, status: status)
            }
        case .itemNotFound:
            throw KeychainSSHKeyPairStoreError.unexpectedStatus(
                operation: .save,
                status: KeychainOperationStatus.itemNotFound.rawStatus
            )
        case .failure(let status):
            throw KeychainSSHKeyPairStoreError.unexpectedStatus(operation: .save, status: status)
        }
    }

    public func deleteKeyPair() async throws {
        try validateConfiguration()

        switch keychain.deleteGenericPassword(service: configuration.service, account: configuration.account) {
        case .success, .itemNotFound:
            return
        case .duplicateItem:
            throw KeychainSSHKeyPairStoreError.unexpectedStatus(
                operation: .delete,
                status: KeychainOperationStatus.duplicateItem.rawStatus
            )
        case .failure(let status):
            throw KeychainSSHKeyPairStoreError.unexpectedStatus(operation: .delete, status: status)
        }
    }

    private func validateConfiguration() throws {
        if configuration.service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KeychainSSHKeyPairStoreError.invalidConfiguration(field: .service)
        }
        if configuration.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KeychainSSHKeyPairStoreError.invalidConfiguration(field: .account)
        }
    }

    private func encodeKeyPair(_ keyPair: SSHKeyPair) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(
                StoredSSHKeyPair(publicKey: keyPair.publicKey.rawValue, privateKeyPEM: keyPair.privateKey.pemString)
            )
        } catch {
            throw KeychainSSHKeyPairStoreError.encodingFailed
        }
    }

    private func decodeKeyPair(from data: Data) throws -> SSHKeyPair {
        let decoder = JSONDecoder()
        do {
            let stored = try decoder.decode(StoredSSHKeyPair.self, from: data)
            let publicKey = try OpenSSHPublicKey(rawValue: stored.publicKey)
            let privateKey = try SSHPrivateKeyMaterial(pemString: stored.privateKeyPEM)
            return SSHKeyPair(publicKey: publicKey, privateKey: privateKey)
        } catch {
            throw KeychainSSHKeyPairStoreError.invalidStoredKeyPair
        }
    }
}

private struct StoredSSHKeyPair: Codable {
    let publicKey: String
    let privateKeyPEM: String
}

struct KeychainGenericPasswordItem: Equatable {
    let service: String
    let account: String
    let data: Data
    let accessibility: KeychainItemAccessibility
}

enum KeychainLookupResult: Equatable {
    case found(Data)
    case notFound
    case failure(Int32)
}

enum KeychainOperationStatus: Equatable {
    case success
    case duplicateItem
    case itemNotFound
    case failure(Int32)

    var rawStatus: Int32 {
        switch self {
        case .success:
            return Int32(errSecSuccess)
        case .duplicateItem:
            return Int32(errSecDuplicateItem)
        case .itemNotFound:
            return Int32(errSecItemNotFound)
        case .failure(let status):
            return status
        }
    }

    init(status: OSStatus) {
        switch status {
        case errSecSuccess:
            self = .success
        case errSecDuplicateItem:
            self = .duplicateItem
        case errSecItemNotFound:
            self = .itemNotFound
        default:
            self = .failure(Int32(status))
        }
    }
}

protocol KeychainAccessing {
    func copyGenericPassword(service: String, account: String) -> KeychainLookupResult
    func addGenericPassword(_ item: KeychainGenericPasswordItem) -> KeychainOperationStatus
    func updateGenericPassword(_ item: KeychainGenericPasswordItem) -> KeychainOperationStatus
    func deleteGenericPassword(service: String, account: String) -> KeychainOperationStatus
}

private struct SystemKeychainAccessor: KeychainAccessing {
    func copyGenericPassword(service: String, account: String) -> KeychainLookupResult {
        var result: CFTypeRef?
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return .found(Data())
            }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failure(Int32(status))
        }
    }

    func addGenericPassword(_ item: KeychainGenericPasswordItem) -> KeychainOperationStatus {
        var attributes = baseQuery(service: item.service, account: item.account)
        attributes[kSecValueData as String] = item.data
        attributes[kSecAttrAccessible as String] = item.accessibility.securityValue

        return KeychainOperationStatus(status: SecItemAdd(attributes as CFDictionary, nil))
    }

    func updateGenericPassword(_ item: KeychainGenericPasswordItem) -> KeychainOperationStatus {
        let query = baseQuery(service: item.service, account: item.account)
        let attributes: [String: Any] = [
            kSecValueData as String: item.data,
            kSecAttrAccessible as String: item.accessibility.securityValue
        ]

        return KeychainOperationStatus(status: SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
    }

    func deleteGenericPassword(service: String, account: String) -> KeychainOperationStatus {
        let query = baseQuery(service: service, account: account)
        return KeychainOperationStatus(status: SecItemDelete(query as CFDictionary))
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}
#endif
