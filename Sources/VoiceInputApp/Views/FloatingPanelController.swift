import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingPreviewView>?
    private var lastContentSize = NSSize(width: 420, height: 48)

    func show(
        state: AppState,
        stop: (() -> Void)?,
        cancel: @escaping () -> Void,
        showsTextPreview: Bool = true,
        asrStatus: String = "",
        actionHint: String = "Space 完成   放弃键放弃"
    ) {
        let content = FloatingPreviewView(
            state: state,
            stop: stop,
            cancel: cancel,
            showsTextPreview: showsTextPreview,
            asrStatus: asrStatus,
            actionHint: actionHint
        )
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 48),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .transient,
                .ignoresCycle
            ]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }
        guard let panel else {
            return
        }
        if let hostingView {
            hostingView.rootView = content
        } else {
            let hostingView = NSHostingView(rootView: content)
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        guard let hostingView else {
            return
        }
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let targetWidth = min(420, max(280, fittingSize.width))
        let targetSize = NSSize(width: targetWidth, height: max(44, fittingSize.height))
        let shouldReposition = !panel.isVisible
        let shouldResize = abs(targetSize.height - lastContentSize.height) > 0.5
            || abs(targetSize.width - lastContentSize.width) > 0.5
        if shouldReposition || shouldResize {
            let targetFrame = shouldReposition
                ? defaultFrame(for: targetSize)
                : frame(for: targetSize, from: panel.frame)
            if panel.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(targetFrame, display: true)
                }
            } else {
                panel.setFrame(targetFrame, display: true)
            }
            lastContentSize = targetSize
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func frame(for contentSize: NSSize, from currentFrame: NSRect) -> NSRect {
        NSRect(
            x: currentFrame.midX - contentSize.width / 2,
            y: currentFrame.minY,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    private func defaultFrame(for contentSize: NSSize) -> NSRect {
        let visibleFrame = currentScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return NSRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }
}
