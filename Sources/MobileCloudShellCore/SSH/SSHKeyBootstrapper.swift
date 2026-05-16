public protocol CloudShellPublicKeyRegistering {
    func addPublicKey(_ key: String) async throws -> CloudShellOperation
}

extension CloudShellAPIClient: CloudShellPublicKeyRegistering {}

public protocol CloudShellOperationPolling {
    func waitUntilDone(_ operation: CloudShellOperation) async throws -> CloudShellOperation
}

extension CloudShellOperationPoller: CloudShellOperationPolling {}

public enum SSHKeyBootstrapError: Error, Equatable, Sendable {
    case rollbackFailed(originalErrorDescription: String, rollbackErrorDescription: String)
}

public struct SSHKeyBootstrapResult: Equatable, Sendable {
    public let keyPair: SSHKeyPair
    public let wasCreated: Bool
    public let registrationOperation: CloudShellOperation?

    public init(
        keyPair: SSHKeyPair,
        wasCreated: Bool,
        registrationOperation: CloudShellOperation?
    ) {
        self.keyPair = keyPair
        self.wasCreated = wasCreated
        self.registrationOperation = registrationOperation
    }
}

public struct SSHKeyBootstrapper {
    private let keyManager: SSHKeyManager
    private let registrar: any CloudShellPublicKeyRegistering
    private let operationPoller: any CloudShellOperationPolling

    public init(
        keyManager: SSHKeyManager,
        registrar: any CloudShellPublicKeyRegistering,
        operationPoller: any CloudShellOperationPolling
    ) {
        self.keyManager = keyManager
        self.registrar = registrar
        self.operationPoller = operationPoller
    }

    public func bootstrapKeyPair(
        preferredAlgorithm: SSHKeyAlgorithm = .ecdsaP256,
        registerExistingKey: Bool = false
    ) async throws -> SSHKeyBootstrapResult {
        let resolution = try await keyManager.resolveKeyPair(preferredAlgorithm: preferredAlgorithm)
        guard resolution.wasCreated || registerExistingKey else {
            return SSHKeyBootstrapResult(
                keyPair: resolution.keyPair,
                wasCreated: resolution.wasCreated,
                registrationOperation: nil
            )
        }

        do {
            let operation = try await registrar.addPublicKey(resolution.keyPair.publicKey.rawValue)
            let completedOperation = try await operationPoller.waitUntilDone(operation)
            return SSHKeyBootstrapResult(
                keyPair: resolution.keyPair,
                wasCreated: resolution.wasCreated,
                registrationOperation: completedOperation
            )
        } catch let operationError {
            if resolution.wasCreated {
                do {
                    try await keyManager.deleteKeyPair()
                } catch let rollbackError {
                    throw SSHKeyBootstrapError.rollbackFailed(
                        originalErrorDescription: RedactedLogger.redact(String(describing: operationError)),
                        rollbackErrorDescription: RedactedLogger.redact(String(describing: rollbackError))
                    )
                }
            }
            throw operationError
        }
    }
}
