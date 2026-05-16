public protocol OAuthClient {
    func signIn() async throws -> AuthSession
    func refreshSession(_ session: AuthSession) async throws -> AuthSession
    func signOut() async throws
}
