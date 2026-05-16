import XCTest
@testable import MobileCloudShellCore

final class CloudShellOperationPollerTests: XCTestCase {
    func testReturnsImmediatelyWhenInitialOperationIsDone() async throws {
        let fetcher = RecordingOperationFetcher(responses: [])
        var sleepCount = 0
        let poller = CloudShellOperationPoller(
            fetcher: fetcher,
            maxAttempts: 3,
            sleep: { sleepCount += 1 }
        )
        let operation = CloudShellOperation(name: "operations/done", done: true)

        let result = try await poller.waitUntilDone(operation)

        XCTAssertEqual(result, operation)
        XCTAssertEqual(fetcher.requestedNames, [])
        XCTAssertEqual(sleepCount, 0)
    }

    func testRetriesPendingOperationNameUntilDone() async throws {
        let fetcher = RecordingOperationFetcher(responses: [
            CloudShellOperation(name: "operations/start", done: false),
            CloudShellOperation(name: "operations/start", done: true)
        ])
        var sleepCount = 0
        let poller = CloudShellOperationPoller(
            fetcher: fetcher,
            maxAttempts: 3,
            sleep: { sleepCount += 1 }
        )

        let result = try await poller.waitUntilDone(CloudShellOperation(name: "operations/start", done: false))

        XCTAssertEqual(result, CloudShellOperation(name: "operations/start", done: true))
        XCTAssertEqual(fetcher.requestedNames, ["operations/start", "operations/start"])
        XCTAssertEqual(sleepCount, 1)
    }

    func testThrowsTimedOutAfterMaxAttempts() async {
        let fetcher = RecordingOperationFetcher(responses: [
            CloudShellOperation(name: "operations/slow", done: false),
            CloudShellOperation(name: "operations/slow", done: false)
        ])
        var sleepCount = 0
        let poller = CloudShellOperationPoller(
            fetcher: fetcher,
            maxAttempts: 2,
            sleep: { sleepCount += 1 }
        )

        await assertThrowsPollerError(.timedOut(operationName: "operations/slow", attempts: 2)) {
            try await poller.waitUntilDone(CloudShellOperation(name: "operations/slow", done: false))
        }
        XCTAssertEqual(fetcher.requestedNames, ["operations/slow", "operations/slow"])
        XCTAssertEqual(sleepCount, 1)
    }

    func testThrowsOperationFailedWhenOperationContainsError() async {
        let operationError = CloudShellOperationError(code: 13, message: "internal failure", status: "INTERNAL")
        let fetcher = RecordingOperationFetcher(responses: [
            CloudShellOperation(name: "operations/fail", done: true, error: operationError)
        ])
        let poller = CloudShellOperationPoller(fetcher: fetcher, maxAttempts: 3, sleep: {})

        await assertThrowsPollerError(.operationFailed(operationError)) {
            try await poller.waitUntilDone(CloudShellOperation(name: "operations/fail", done: false))
        }
    }

    func testOperationFailureDescriptionRedactsSecrets() async {
        let rawToken = "raw-access-token"
        let operationError = CloudShellOperationError(
            code: 7,
            message: "failed for Bearer \(rawToken) and accessToken=\(rawToken)",
            status: "PERMISSION_DENIED"
        )
        let fetcher = RecordingOperationFetcher(responses: [
            CloudShellOperation(name: "operations/fail", done: true, error: operationError)
        ])
        let poller = CloudShellOperationPoller(fetcher: fetcher, maxAttempts: 1, sleep: {})

        do {
            _ = try await poller.waitUntilDone(operationName: "operations/fail")
            XCTFail("Expected operation failure")
        } catch let error as CloudShellError {
            XCTAssertFalse(error.localizedDescription.contains(rawToken))
            XCTAssertTrue(error.localizedDescription.contains("<redacted>"))
        } catch {
            XCTFail("Expected CloudShellError, got \(error)")
        }
    }
}

private func assertThrowsPollerError<T>(
    _ expected: CloudShellError,
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected CloudShellError.\(expected)", file: file, line: line)
    } catch let error as CloudShellError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected CloudShellError.\(expected), got \(error)", file: file, line: line)
    }
}

private final class RecordingOperationFetcher: OperationFetching {
    private(set) var requestedNames: [String] = []
    private var responses: [CloudShellOperation]

    init(responses: [CloudShellOperation]) {
        self.responses = responses
    }

    func fetchOperation(named name: String) async throws -> CloudShellOperation {
        requestedNames.append(name)
        return responses.removeFirst()
    }
}
