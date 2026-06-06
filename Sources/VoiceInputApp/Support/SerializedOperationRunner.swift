import Foundation

@MainActor
public final class SerializedOperationRunner {
    private var currentTask: Task<Void, Never>?
    private var pendingOperation: (@MainActor () async -> Void)?

    public var isRunning: Bool {
        currentTask != nil
    }

    public init() {}

    public func run(_ operation: @escaping @MainActor () async -> Void) {
        guard currentTask == nil else {
            pendingOperation = operation
            return
        }

        start(operation)
    }

    public func cancel() {
        pendingOperation = nil
        currentTask?.cancel()
        currentTask = nil
    }

    private func start(_ operation: @escaping @MainActor () async -> Void) {
        currentTask = Task { @MainActor in
            await operation()
            currentTask = nil
            if let pendingOperation {
                self.pendingOperation = nil
                start(pendingOperation)
            }
        }
    }
}
