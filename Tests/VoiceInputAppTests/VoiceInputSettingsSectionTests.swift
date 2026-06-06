import XCTest
@testable import VoiceInputApp

final class VoiceInputSettingsSectionTests: XCTestCase {
    func testSettingsSectionsUseStableChineseOrder() {
        XCTAssertEqual(
            VoiceInputSettingsSection.allCases.map(\.title),
            ["总览", "快捷键", "识别与 ASR", "大模型", "高频词组", "提示词", "浮窗", "诊断", "最近输入"]
        )
    }

    func testSettingsSectionsHaveSidebarIcons() {
        XCTAssertTrue(VoiceInputSettingsSection.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
