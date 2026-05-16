import XCTest
@testable import MobileCloudShellCore

final class WorkspaceMetadataStoreTests: XCTestCase {
    func testDecodesMetadataAndAppliesDisplayNameToLiveSession() throws {
        let store = WorkspaceMetadataStore()
        let metadata = try store.decode(Self.metadataJSON.data(using: .utf8)!)
        let sessions = [Self.liveSession(named: "mobile-agent_20260516-1530_a")]

        let workspaces = store.merge(liveSessions: sessions, metadata: metadata)

        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces[0].sessionName, "mobile-agent_20260516-1530_a")
        XCTAssertEqual(workspaces[0].displayName, "Codex: iOS PRD 정리")
        XCTAssertEqual(workspaces[0].windowCount, 1)
        XCTAssertEqual(workspaces[0].attachedClientCount, 0)
    }

    func testUsesFallbackDisplayNameWhenMetadataIsMissing() {
        let store = WorkspaceMetadataStore()
        let sessions = [Self.liveSession(named: "mobile-agent_20260516-1530_b")]

        let workspaces = store.merge(liveSessions: sessions, metadata: .empty)

        XCTAssertEqual(workspaces.map(\.displayName), ["Workspace 15:30 b"])
    }

    func testStaleMetadataWithoutLiveTmuxSessionIsNotReturned() throws {
        let store = WorkspaceMetadataStore()
        let metadata = try store.decode(Self.metadataJSON.data(using: .utf8)!)
        let sessions = [Self.liveSession(named: "mobile-agent_20260516-1530_b")]

        let workspaces = store.merge(liveSessions: sessions, metadata: metadata)

        XCTAssertEqual(workspaces.map(\.sessionName), ["mobile-agent_20260516-1530_b"])
        XCTAssertEqual(workspaces.map(\.displayName), ["Workspace 15:30 b"])
    }

    func testEncodesMetadataAsSchemaVersionOneJSON() throws {
        let store = WorkspaceMetadataStore()
        let metadata = WorkspaceMetadataFile(
            schemaVersion: 1,
            workspaces: [
                "mobile-agent_20260516-1530_a": WorkspaceMetadata(
                    displayName: "Codex: iOS PRD 정리",
                    createdAt: fixedDate("2026-05-16T06:30:00Z"),
                    updatedAt: fixedDate("2026-05-16T06:45:12Z"),
                    lastOpenedAt: fixedDate("2026-05-16T07:01:03Z")
                )
            ]
        )

        let encoded = try store.encode(metadata)
        let decoded = try store.decode(encoded)

        XCTAssertEqual(decoded, metadata)
    }

    func testRejectsUnsupportedSchemaVersion() {
        let store = WorkspaceMetadataStore()
        let data = "{\"schemaVersion\":2,\"workspaces\":{}}".data(using: .utf8)!

        XCTAssertThrowsError(try store.decode(data)) { error in
            XCTAssertEqual(error as? WorkspaceMetadataStore.StoreError, .unsupportedSchemaVersion(2))
        }
    }

    private static let metadataJSON = """
    {
      "schemaVersion": 1,
      "workspaces": {
        "mobile-agent_20260516-1530_a": {
          "displayName": "Codex: iOS PRD 정리",
          "createdAt": "2026-05-16T06:30:00Z",
          "updatedAt": "2026-05-16T06:45:12Z",
          "lastOpenedAt": "2026-05-16T07:01:03Z"
        }
      }
    }
    """

    private static func liveSession(named name: String) -> TmuxSession {
        TmuxSession(
            name: name,
            createdAt: fixedDate("2026-05-16T06:30:00Z"),
            lastActivityAt: fixedDate("2026-05-16T06:45:00Z"),
            windowCount: 1,
            attachedClientCount: 0
        )
    }
}

private func fixedDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value)!
}
