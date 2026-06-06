import XCTest
@testable import VoiceInputApp

final class LaunchAtLoginServiceTests: XCTestCase {
    func testPreferenceUpdaterCallsControllerAndUpdatesPreference() throws {
        let controller = RecordingLaunchAtLoginController()
        let updater = LaunchAtLoginPreferenceUpdater(controller: controller)

        let updated = try updater.preferencesByApplying(true, to: .defaults)

        XCTAssertEqual(controller.recordedValues, [true])
        XCTAssertEqual(updated.launchAtLoginEnabled, true)
    }
}

private final class RecordingLaunchAtLoginController: LaunchAtLoginControlling, @unchecked Sendable {
    private(set) var recordedValues: [Bool] = []

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        recordedValues.append(isEnabled)
    }
}
