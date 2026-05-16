public protocol SSHKeyPairStore {
    func loadKeyPair() async throws -> SSHKeyPair?
    func saveKeyPair(_ keyPair: SSHKeyPair) async throws
    func deleteKeyPair() async throws
}

public protocol SSHKeyGenerating {
    func generateKeyPair(algorithm: SSHKeyAlgorithm) async throws -> SSHKeyPair
}

public struct SSHKeyResolution: Equatable, Sendable {
    public let keyPair: SSHKeyPair
    public let wasCreated: Bool

    public init(keyPair: SSHKeyPair, wasCreated: Bool) {
        self.keyPair = keyPair
        self.wasCreated = wasCreated
    }
}

public struct SSHKeyManager {
    private let store: any SSHKeyPairStore
    private let generator: any SSHKeyGenerating

    public init(store: any SSHKeyPairStore, generator: any SSHKeyGenerating) {
        self.store = store
        self.generator = generator
    }

    public func resolveKeyPair(
        preferredAlgorithm: SSHKeyAlgorithm = .ecdsaP256
    ) async throws -> SSHKeyResolution {
        if let existing = try await store.loadKeyPair() {
            return SSHKeyResolution(keyPair: existing, wasCreated: false)
        }

        let generated = try await generator.generateKeyPair(algorithm: preferredAlgorithm)
        guard generated.algorithm == preferredAlgorithm else {
            throw SSHKeyError.algorithmMismatch(expected: preferredAlgorithm, actual: generated.algorithm)
        }

        try await store.saveKeyPair(generated)
        return SSHKeyResolution(keyPair: generated, wasCreated: true)
    }

    public func loadOrCreateKeyPair(
        preferredAlgorithm: SSHKeyAlgorithm = .ecdsaP256
    ) async throws -> SSHKeyPair {
        let resolution = try await resolveKeyPair(preferredAlgorithm: preferredAlgorithm)
        return resolution.keyPair
    }

    public func deleteKeyPair() async throws {
        try await store.deleteKeyPair()
    }
}
