import XCTest
@testable import MobileCloudShellCore

final class WorkspaceNameGeneratorTests: XCTestCase {
    func testFirstSessionForMinuteUsesSuffixA() throws {
        let generator = WorkspaceNameGenerator()

        let name = try generator.makeName(
            for: fixedDate("2026-05-16T15:30:00Z"),
            existingSessionNames: []
        )

        XCTAssertEqual(name, "mobile-agent_20260516-1530_a")
    }

    func testSkipsExistingSuffixesInTheSameMinute() throws {
        let generator = WorkspaceNameGenerator()

        let secondName = try generator.makeName(
            for: fixedDate("2026-05-16T15:30:30Z"),
            existingSessionNames: ["mobile-agent_20260516-1530_a"]
        )

        XCTAssertEqual(secondName, "mobile-agent_20260516-1530_b")

        let existing: Set<String> = [secondName, "mobile-agent_20260516-1530_a"]
        let thirdName = try generator.makeName(
            for: fixedDate("2026-05-16T15:30:45Z"),
            existingSessionNames: existing
        )

        XCTAssertEqual(thirdName, "mobile-agent_20260516-1530_c")
    }

    func testUsesUppercaseSuffixAfterLowercaseZ() throws {
        let generator = WorkspaceNameGenerator()
        let lowercaseNames = Array("abcdefghijklmnopqrstuvwxyz")
            .map { "mobile-agent_20260516-1530_\($0)" }

        let name = try generator.makeName(
            for: fixedDate("2026-05-16T15:30:00Z"),
            existingSessionNames: Set(lowercaseNames)
        )

        XCTAssertEqual(name, "mobile-agent_20260516-1530_A")
    }

    func testThrowsUserActionableErrorWhenAllSuffixesAreExhausted() {
        let generator = WorkspaceNameGenerator()
        let suffixes = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let existing = Set(suffixes.map { "mobile-agent_20260516-1530_\($0)" })

        XCTAssertThrowsError(
            try generator.makeName(
                for: fixedDate("2026-05-16T15:30:00Z"),
                existingSessionNames: existing
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceNameGenerationError,
                .suffixesExhausted(prefix: "mobile-agent_20260516-1530")
            )
            XCTAssertEqual(
                error.localizedDescription,
                "No available one-letter workspace suffix remains for mobile-agent_20260516-1530. Ask the user to enter a name or wait until the next minute."
            )
        }
    }

    func testManagedSessionNameValidationRequiresStrictGeneratedShape() {
        XCTAssertTrue(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_20260516-1530_a"))
        XCTAssertTrue(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_20260516-1530_Z"))

        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("desktop-agent_20260516-1530_a"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_bad"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_20260516-1530_aa"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_20260516-1530_a;tmux kill-server"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_20260516-1530_\n"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_2026051x-1530_a"))
        XCTAssertFalse(WorkspaceNameGenerator.isManagedSessionName("mobile-agent_20260516_1530_a"))
    }
}

private func fixedDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value)!
}
