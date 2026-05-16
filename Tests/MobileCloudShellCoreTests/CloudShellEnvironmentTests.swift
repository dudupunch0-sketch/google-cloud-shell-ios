import XCTest
@testable import MobileCloudShellCore

final class CloudShellEnvironmentTests: XCTestCase {
    func testEnvironmentIsSSHConnectableOnlyWhenAllSSHFieldsArePresent() {
        XCTAssertTrue(
            CloudShellEnvironment(
                name: "users/me/environments/default",
                state: .running,
                sshUsername: "user",
                sshHost: "host",
                sshPort: 6000
            ).isSSHConnectable
        )

        XCTAssertFalse(
            CloudShellEnvironment(
                name: "users/me/environments/default",
                state: .running,
                sshUsername: "user",
                sshHost: nil,
                sshPort: 6000
            ).isSSHConnectable
        )
    }

    func testStateDecodingMapsKnownAPIValues() throws {
        let decoded = try JSONDecoder().decode(
            CloudShellEnvironment.State.self,
            from: Data("\"RUNNING\"".utf8)
        )

        XCTAssertEqual(decoded, .running)
    }

    func testStateDecodingPreservesUnexpectedAPIValuesAsUnknown() throws {
        let decoded = try JSONDecoder().decode(
            CloudShellEnvironment.State.self,
            from: Data("\"NEW_STATE_FROM_API\"".utf8)
        )

        XCTAssertEqual(decoded, .unknown)
    }
}
