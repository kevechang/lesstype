import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let onRecord: (HotkeyShortcut) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onRecord = onRecord
        context.coordinator.setRecording(isRecording)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecord: onRecord)
    }

    final class Coordinator {
        var onRecord: (HotkeyShortcut) -> Void

        private var monitor: Any?
        private var isFunctionDown = false
        private var didCaptureChord = false

        init(onRecord: @escaping (HotkeyShortcut) -> Void) {
            self.onRecord = onRecord
        }

        deinit {
            setRecording(false)
        }

        func setRecording(_ isRecording: Bool) {
            if isRecording, monitor == nil {
                isFunctionDown = false
                didCaptureChord = false
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    self?.handle(event)
                }
            } else if !isRecording, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
                isFunctionDown = false
                didCaptureChord = false
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .flagsChanged:
                handleFlagsChanged(event)
            case .keyDown:
                recordKeyEvent(event)
            default:
                break
            }
            return nil
        }

        private func handleFlagsChanged(_ event: NSEvent) {
            guard Int64(event.keyCode) == HotkeyKeyCode.function else {
                return
            }

            let hasFunctionFlag = event.modifierFlags.contains(.function)
            if hasFunctionFlag {
                isFunctionDown = true
                didCaptureChord = false
            } else if isFunctionDown, !didCaptureChord {
                onRecord(.recorded(
                    keyCode: HotkeyKeyCode.function,
                    modifierFlags: HotkeyModifier.function.rawValue
                ))
            }
        }

        private func recordKeyEvent(_ event: NSEvent) {
            let functionFlag = isFunctionDown ? HotkeyModifier.function.rawValue : 0
            didCaptureChord = true
            onRecord(.recorded(
                keyCode: Int64(event.keyCode),
                modifierFlags: UInt64(event.modifierFlags.rawValue) | functionFlag
            ))
        }
    }
}
