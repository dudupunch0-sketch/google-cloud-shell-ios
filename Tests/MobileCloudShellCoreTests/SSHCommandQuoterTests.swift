import XCTest
@testable import MobileCloudShellCore

final class SSHCommandQuoterTests: XCTestCase {
    func testQuotesEmptyArgument() {
        XCTAssertEqual(SSHCommandQuoter.quote(""), "''")
    }

    func testQuotesPlainArgument() {
        XCTAssertEqual(SSHCommandQuoter.quote("abc"), "'abc'")
    }

    func testQuotesWhitespaceArgument() {
        XCTAssertEqual(SSHCommandQuoter.quote("hello world"), "'hello world'")
    }

    func testQuotesApostropheArgument() {
        XCTAssertEqual(SSHCommandQuoter.quote("a'b"), "'a'\\''b'")
    }

    func testQuotesNewlineArgument() {
        XCTAssertEqual(SSHCommandQuoter.quote("line1\nline2"), "'line1\nline2'")
    }

    func testJoinsCommandArguments() {
        XCTAssertEqual(
            SSHCommandQuoter.join(["tmux", "new-session", "name with space"]),
            "'tmux' 'new-session' 'name with space'"
        )
    }
}
