import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        expiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresAt = expiresAt
    }

    public var authorizationHeader: String {
        "Bearer \(accessToken)"
    }

    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt <= date.addingTimeInterval(leeway)
    }
}
