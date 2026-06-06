import Foundation

public enum HotkeyDiagnostics {
    public static func warnings(for preferences: Preferences) -> [String] {
        var warnings: [String] = []
        let shortcuts: [(name: String, shortcut: HotkeyShortcut)] = [
            ("普通记录", preferences.ordinaryHotkey),
            ("自动分点", preferences.structuredHotkey),
            ("结束并插入", preferences.cancelHotkey),
            ("放弃本次内容", preferences.resolvedDiscardHotkey)
        ]

        for pair in duplicatedShortcutPairs(shortcuts) {
            warnings.append("\(pair.first) 和 \(pair.second) 使用了同一个快捷键，后触发的动作可能不稳定。")
        }

        for item in shortcuts where usesFunctionModifier(item.shortcut) {
            warnings.append("\(item.name) 使用了 Fn 组合。Fn 在部分键盘和系统版本下不能稳定注册为全局快捷键。")
        }

        for item in shortcuts where isKnownSystemShortcut(item.shortcut) {
            warnings.append("\(item.name) 使用了常见系统快捷键 \(item.shortcut.displayName)，建议换成 control/option/command 与字母组合。")
        }

        return warnings
    }

    public static func summary(for preferences: Preferences) -> String {
        let warnings = warnings(for: preferences)
        return warnings.isEmpty ? "快捷键配置未发现明显风险。" : warnings.joined(separator: "\n")
    }

    private static func duplicatedShortcutPairs(
        _ shortcuts: [(name: String, shortcut: HotkeyShortcut)]
    ) -> [(first: String, second: String)] {
        var pairs: [(String, String)] = []
        for firstIndex in shortcuts.indices {
            for secondIndex in shortcuts.indices where secondIndex > firstIndex {
                if shortcuts[firstIndex].shortcut.matchesIdentity(of: shortcuts[secondIndex].shortcut) {
                    pairs.append((shortcuts[firstIndex].name, shortcuts[secondIndex].name))
                }
            }
        }
        return pairs
    }

    private static func usesFunctionModifier(_ shortcut: HotkeyShortcut) -> Bool {
        shortcut.kind == .functionOnly ||
            HotkeyModifier(rawValue: shortcut.modifierFlags).contains(.function)
    }

    private static func isKnownSystemShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        guard shortcut.kind == .key else {
            return false
        }
        let modifiers = HotkeyModifier(rawValue: shortcut.modifierFlags)
        return shortcut.keyCode == HotkeyKeyCode.space &&
            (modifiers == .command || modifiers == .control)
    }
}

private extension HotkeyShortcut {
    func matchesIdentity(of other: HotkeyShortcut) -> Bool {
        kind == other.kind &&
            keyCode == other.keyCode &&
            modifierFlags == other.modifierFlags
    }
}
