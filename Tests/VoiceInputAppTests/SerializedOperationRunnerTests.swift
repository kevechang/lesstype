import XCTest
@testable import VoiceInputApp

@MainActor
final class SerializedOperationRunnerTests: XCTestCase {
    func testQueuedOperationRunsAfterCurrentOperationFinishes() async {
        let runner = SerializedOperationRunner()
        let gate = OperationGate()
        var events: [String] = []

        runner.run {
            events.append("first-start")
            while !gate.canFinish {
                await Task.yield()
            }
            events.append("first-end")
        }

        await waitUntil { events == ["first-start"] }

        runner.run {
            events.append("second")
        }

        XCTAssertEqual(events, ["first-start"])
        gate.canFinish = true

        await waitUntil { events == ["first-start", "first-end", "second"] }
        XCTAssertFalse(runner.isRunning)
    }

    func testLatestQueuedOperationReplacesEarlierQueuedOperation() async {
        let runner = SerializedOperationRunner()
        let gate = OperationGate()
        var events: [String] = []

        runner.run {
            events.append("first")
            while !gate.canFinish {
                await Task.yield()
            }
        }

        await waitUntil { events == ["first"] }

        runner.run {
            events.append("second")
        }
        runner.run {
            events.append("third")
        }

        gate.canFinish = true

        await waitUntil { events == ["first", "third"] }
        XCTAssertFalse(runner.isRunning)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not met before timeout", file: file, line: line)
    }
}

@MainActor
private final class OperationGate {
    var canFinish = false
}
