import AppKit
import ApplicationServices

@MainActor
public protocol TextTyping: AnyObject {
    func type(_ text: String) async throws
}

@MainActor
public final class TextInsertionService: TextInsertionServing {
    private let accessibilityPermission: () -> Bool
    private let textTyper: TextTyping

    public init(
        accessibilityPermission: @escaping () -> Bool = { AXIsProcessTrusted() },
        textTyper: TextTyping = CGEventTextTyper()
    ) {
        self.accessibilityPermission = accessibilityPermission
        self.textTyper = textTyper
    }

    public func insert(_ text: String) async throws {
        guard accessibilityPermission() else {
            throw TextInsertionError.accessibilityPermissionMissing
        }
        try await textTyper.type(text)
    }
}

@MainActor
public final class CGEventTextTyper: TextTyping {
    private let chunkSize: Int
    private let chunkDelayNanoseconds: UInt64

    public init(chunkSize: Int = 32, chunkDelayNanoseconds: UInt64 = 2_000_000) {
        self.chunkSize = chunkSize
        self.chunkDelayNanoseconds = chunkDelayNanoseconds
    }

    public func type(_ text: String) async throws {
        let units = Array(text.utf16)
        guard !units.isEmpty else {
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw TextInsertionError.eventCreationFailed
        }

        var index = 0
        while index < units.count {
            let end = min(index + chunkSize, units.count)
            let chunk = Array(units[index..<end])
            try post(chunk, source: source)
            index = end
            if index < units.count {
                try await Task.sleep(nanoseconds: chunkDelayNanoseconds)
            }
        }
    }

    private func post(_ units: [UInt16], source: CGEventSource) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw TextInsertionError.eventCreationFailed
        }

        units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

public enum TextInsertionError: LocalizedError {
    case accessibilityPermissionMissing
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "需要开启辅助功能权限，才能把文字直接输入到当前应用。"
        case .eventCreationFailed:
            "无法创建直接输入键盘事件。"
        }
    }
}
