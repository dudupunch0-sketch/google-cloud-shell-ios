import Foundation

public struct CloudShellOperation: Equatable, Sendable {
    public let name: String
    public let done: Bool
    public let error: CloudShellOperationError?

    public init(name: String, done: Bool = false, error: CloudShellOperationError? = nil) {
        self.name = name
        self.done = done
        self.error = error
    }
}

public protocol OperationFetching {
    func fetchOperation(named name: String) async throws -> CloudShellOperation
}

public struct CloudShellOperationPoller {
    public typealias Sleep = () async throws -> Void

    private let fetcher: any OperationFetching
    private let maxAttempts: Int
    private let sleep: Sleep

    public init(
        fetcher: any OperationFetching,
        maxAttempts: Int = 30,
        sleep: @escaping Sleep = {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    ) {
        self.fetcher = fetcher
        self.maxAttempts = maxAttempts
        self.sleep = sleep
    }

    public func waitUntilDone(_ operation: CloudShellOperation) async throws -> CloudShellOperation {
        if let error = operation.error {
            throw CloudShellError.operationFailed(error)
        }
        if operation.done {
            return operation
        }
        return try await waitUntilDone(operationName: operation.name)
    }

    public func waitUntilDone(operationName: String) async throws -> CloudShellOperation {
        guard maxAttempts > 0 else {
            throw CloudShellError.timedOut(operationName: operationName, attempts: maxAttempts)
        }

        for attempt in 1...maxAttempts {
            let operation = try await fetcher.fetchOperation(named: operationName)
            if let error = operation.error {
                throw CloudShellError.operationFailed(error)
            }
            if operation.done {
                return operation
            }
            if attempt < maxAttempts {
                try await sleep()
            }
        }

        throw CloudShellError.timedOut(operationName: operationName, attempts: maxAttempts)
    }
}
