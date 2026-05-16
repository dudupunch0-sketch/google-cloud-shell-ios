public protocol AuthSessionCodableStorage {
    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value?
    func save<Value: Encodable>(_ value: Value, forKey key: String) throws
    func delete(forKey key: String) throws
}

public struct AuthSessionStore {
    public static let defaultKey = "auth.session"

    private let storage: any AuthSessionCodableStorage
    private let key: String

    public init(storage: any AuthSessionCodableStorage, key: String = AuthSessionStore.defaultKey) {
        self.storage = storage
        self.key = key
    }

    public func load() throws -> AuthSession? {
        try storage.load(AuthSession.self, forKey: key)
    }

    public func save(_ session: AuthSession) throws {
        try storage.save(session, forKey: key)
    }

    public func delete() throws {
        try storage.delete(forKey: key)
    }
}
