import XCTest
@testable import VoiceInputApp

final class HotkeyServiceTests: XCTestCase {
    func testSingleFunctionKeyCommitsOnRelease() {
        let parser = HotkeyEventParser()
        let preferences = Self.legacyFunctionKeyPreferences()

        XCTAssertNil(parser.action(for: functionDown()))
        XCTAssertEqual(parser.action(for: functionUp(), preferences: preferences), .commitCurrent)
    }

    func testFunctionZDoesNotCancelOnFunctionRelease() {
        let parser = HotkeyEventParser()
        let preferences = Self.legacyFunctionKeyPreferences()

        XCTAssertNil(parser.action(for: functionDown(), preferences: preferences))
        XCTAssertEqual(parser.action(for: keyDown(HotkeyKeyCode.z, hasFunctionFlag: true), preferences: preferences), .toggleOrdinary)
        XCTAssertNil(parser.action(for: functionUp(), preferences: preferences))
    }

    func testFunctionXDoesNotCancelOnFunctionRelease() {
        let parser = HotkeyEventParser()
        let preferences = Self.legacyFunctionKeyPreferences()

        XCTAssertNil(parser.action(for: functionDown(), preferences: preferences))
        XCTAssertEqual(parser.action(for: keyDown(HotkeyKeyCode.x, hasFunctionFlag: true), preferences: preferences), .toggleStructured)
        XCTAssertNil(parser.action(for: functionUp(), preferences: preferences))
    }

    func testFunctionXWorksWhenLetterEventDoesNotCarryFunctionFlag() {
        let parser = HotkeyEventParser()
        let preferences = Self.legacyFunctionKeyPreferences()

        XCTAssertNil(parser.action(for: functionDown(), preferences: preferences))
        XCTAssertEqual(parser.action(for: keyDown(HotkeyKeyCode.x, hasFunctionFlag: false), preferences: preferences), .toggleStructured)
        XCTAssertNil(parser.action(for: functionUp(), preferences: preferences))
    }

    func testPlainXDoesNotTriggerWithoutFunctionHold() {
        let parser = HotkeyEventParser()

        XCTAssertNil(parser.action(for: keyDown(HotkeyKeyCode.x, hasFunctionFlag: false)))
    }

    func testCustomStructuredShortcutTriggersWithoutFunctionKey() {
        let parser = HotkeyEventParser()
        var preferences = Preferences.defaults
        preferences.structuredHotkey = HotkeyShortcut(
            kind: .key,
            keyCode: 49,
            modifierFlags: HotkeyModifier.control.rawValue | HotkeyModifier.option.rawValue,
            displayName: "control+option+space"
        )

        XCTAssertEqual(
            parser.action(
                for: keyDown(
                    49,
                    hasFunctionFlag: false,
                    modifierFlags: HotkeyModifier.control.rawValue | HotkeyModifier.option.rawValue
                ),
                preferences: preferences
            ),
            .toggleStructured
        )
    }

    func testCustomCommitShortcutTriggersAndEscStillDiscards() {
        let parser = HotkeyEventParser()
        var preferences = Preferences.defaults
        preferences.cancelHotkey = HotkeyShortcut(
            kind: .key,
            keyCode: 8,
            modifierFlags: HotkeyModifier.command.rawValue,
            displayName: "command+c"
        )

        XCTAssertEqual(
            parser.action(
                for: keyDown(8, hasFunctionFlag: false, modifierFlags: HotkeyModifier.command.rawValue),
                preferences: preferences
            ),
            .commitCurrent
        )
        XCTAssertEqual(parser.action(for: keyDown(HotkeyKeyCode.escape, hasFunctionFlag: false), preferences: preferences), .discard)
    }

    func testShortcutDisplayNameUsesRecordedEvent() {
        let shortcut = HotkeyShortcut.recorded(
            keyCode: 7,
            modifierFlags: HotkeyModifier.control.rawValue | HotkeyModifier.option.rawValue
        )

        XCTAssertEqual(shortcut.displayName, "control+option+x")
    }

    func testCarbonModifiersRejectFunctionShortcuts() {
        let shortcut = HotkeyShortcut.recorded(
            keyCode: 7,
            modifierFlags: HotkeyModifier.function.rawValue | HotkeyModifier.option.rawValue
        )

        XCTAssertNil(shortcut.carbonModifierFlags)
    }

    func testCarbonModifiersMapSupportedModifiers() {
        let shortcut = HotkeyShortcut.recorded(
            keyCode: 7,
            modifierFlags: HotkeyModifier.control.rawValue | HotkeyModifier.option.rawValue
        )

        XCTAssertNotNil(shortcut.carbonModifierFlags)
    }

    func testEscapeDiscardsWithoutFunctionKey() {
        let parser = HotkeyEventParser()

        XCTAssertEqual(parser.action(for: keyDown(HotkeyKeyCode.escape, hasFunctionFlag: false)), .discard)
    }

    func testSpaceCommitsActiveSession() {
        XCTAssertEqual(keyDown(HotkeyKeyCode.space, hasFunctionFlag: false).activeSessionAction(preferences: .defaults), .commitCurrent)
    }

    func testNonSpaceKeysDoNotCommitActiveSession() {
        XCTAssertNil(keyDown(0, hasFunctionFlag: false).activeSessionAction(preferences: .defaults))
        XCTAssertNil(keyDown(HotkeyKeyCode.x, hasFunctionFlag: false).activeSessionAction(preferences: .defaults))
    }

    func testEscapeStillDiscardsActiveSession() {
        XCTAssertEqual(keyDown(HotkeyKeyCode.escape, hasFunctionFlag: false).activeSessionAction(preferences: .defaults), .discard)
    }

    func testCustomDiscardHotkeyDiscardsActiveSession() {
        var preferences = Preferences.defaults
        preferences.discardHotkey = HotkeyShortcut(
            kind: .key,
            keyCode: 8,
            modifierFlags: HotkeyModifier.command.rawValue,
            displayName: "command+c"
        )

        XCTAssertEqual(
            keyDown(8, hasFunctionFlag: false, modifierFlags: HotkeyModifier.command.rawValue)
                .activeSessionAction(preferences: preferences),
            .discard
        )
        XCTAssertNil(keyDown(HotkeyKeyCode.escape, hasFunctionFlag: false).activeSessionAction(preferences: preferences))
    }

    func testModifierChangeDoesNotCommitActiveSession() {
        XCTAssertNil(functionDown().activeSessionAction(preferences: .defaults))
        XCTAssertNil(functionUp().activeSessionAction(preferences: .defaults))
    }

    func testSessionActivityTracksActiveFlag() {
        let activity = HotkeySessionActivity()

        XCTAssertFalse(activity.isActive)
        activity.setActive(true)
        XCTAssertTrue(activity.isActive)
        activity.setActive(false)
        XCTAssertFalse(activity.isActive)
    }

    func testSessionActivityClaimsActiveActionOnce() {
        let activity = HotkeySessionActivity()
        activity.setActive(true)

        XCTAssertEqual(activity.claim(.commitCurrent), .commitCurrent)
        XCTAssertFalse(activity.isActive)
        XCTAssertNil(activity.claim(.commitCurrent))
    }

    func testHotkeyDiagnosticsWarnsAboutDuplicateShortcuts() {
        var preferences = Preferences.defaults
        preferences.structuredHotkey = preferences.ordinaryHotkey

        let warnings = HotkeyDiagnostics.warnings(for: preferences)

        XCTAssertTrue(warnings.contains { $0.contains("普通记录") && $0.contains("自动分点") })
    }

    func testHotkeyDiagnosticsWarnsAboutFunctionModifier() {
        var preferences = Preferences.defaults
        preferences.ordinaryHotkey = HotkeyShortcut(
            kind: .key,
            keyCode: HotkeyKeyCode.z,
            modifierFlags: HotkeyModifier.function.rawValue,
            displayName: "fn+z"
        )

        let warnings = HotkeyDiagnostics.warnings(for: preferences)

        XCTAssertTrue(warnings.contains { $0.contains("Fn") || $0.contains("fn") })
    }

    private func functionDown() -> HotkeyEventSnapshot {
        HotkeyEventSnapshot(
            kind: .flagsChanged,
            keyCode: HotkeyKeyCode.function,
            hasFunctionFlag: true
        )
    }

    private func functionUp() -> HotkeyEventSnapshot {
        HotkeyEventSnapshot(
            kind: .flagsChanged,
            keyCode: HotkeyKeyCode.function,
            hasFunctionFlag: false
        )
    }

    private func keyDown(
        _ keyCode: Int64,
        hasFunctionFlag: Bool,
        modifierFlags: UInt64 = 0
    ) -> HotkeyEventSnapshot {
        HotkeyEventSnapshot(
            kind: .keyDown,
            keyCode: keyCode,
            hasFunctionFlag: hasFunctionFlag,
            modifierFlags: modifierFlags
        )
    }
}

private extension HotkeyServiceTests {
    static func legacyFunctionKeyPreferences() -> Preferences {
        var preferences = Preferences.defaults
        preferences.ordinaryHotkey = HotkeyShortcut(kind: .key, keyCode: 6, modifierFlags: HotkeyModifier.function.rawValue, displayName: "fn+z")
        preferences.structuredHotkey = HotkeyShortcut(kind: .key, keyCode: 7, modifierFlags: HotkeyModifier.function.rawValue, displayName: "fn+x")
        preferences.cancelHotkey = HotkeyShortcut(kind: .functionOnly, keyCode: 63, modifierFlags: HotkeyModifier.function.rawValue, displayName: "Fn")
        return preferences
    }
}
