import AVFoundation
import ApplicationServices
import Foundation
import AppKit
import Speech

public struct PermissionSnapshot: Equatable, Sendable {
    public let microphoneGranted: Bool
    public let speechGranted: Bool
    public let accessibilityGranted: Bool
}

public struct PermissionService: Sendable {
    public init() {}

    public func snapshot() async -> PermissionSnapshot {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        let accessibility = AXIsProcessTrusted()
        return PermissionSnapshot(
            microphoneGranted: microphone,
            speechGranted: speech,
            accessibilityGranted: accessibility
        )
    }

    public func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    @discardableResult
    public func requestAccessibilityPrompt() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
