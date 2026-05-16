import XCTest
@testable import MobileCloudShellCore

final class TmuxSessionParserTests: XCTestCase {
    func testParsesManagedTmuxSessionLines() {
        let output = "mobile-agent_20260516-1530_a|1778935800|1778935900|2|1\n"

        let sessions = TmuxSessionParser().parse(output)

        XCTAssertEqual(sessions, [
            TmuxSession(
                name: "mobile-agent_20260516-1530_a",
                createdAt: Date(timeIntervalSince1970: 1_778_935_800),
                lastActivityAt: Date(timeIntervalSince1970: 1_778_935_900),
                windowCount: 2,
                attachedClientCount: 1
            )
        ])
    }

    func testFiltersNonAppManagedSessions() {
        let output = """
        0|1778935800|1778935900|1|1
        mobile-agent_20260516-1530_a|1778935800|1778935900|2|0
        unrelated|1778935800|1778935900|1|0
        """

        let sessions = TmuxSessionParser().parse(output)

        XCTAssertEqual(sessions.map(\.name), ["mobile-agent_20260516-1530_a"])
    }

    func testIgnoresMalformedLinesWithoutDroppingValidSessions() {
        let output = """
        mobile-agent_20260516-1530_a|1778935800|1778935900|2|0
        mobile-agent_bad_line
        mobile-agent_20260516-1530_a;tmux kill-server|1778935800|1778935900|1|0
        mobile-agent_20260516-1530_b|bad|1778935900|1|0
        mobile-agent_20260516-1530_c|1778935800|1778935900|1|0
        """

        let sessions = TmuxSessionParser().parse(output)

        XCTAssertEqual(
            sessions.map(\.name),
            ["mobile-agent_20260516-1530_a", "mobile-agent_20260516-1530_c"]
        )
    }
}
