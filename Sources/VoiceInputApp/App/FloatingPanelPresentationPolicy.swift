enum FloatingPanelPresentationPolicy {
    static func shouldShow(_ state: AppState, mode: FloatingPanelDisplayMode) -> Bool {
        if case .error = state {
            return true
        }
        guard mode != .hidden else {
            return false
        }

        return switch state {
        case .recording, .recognizing, .previewing, .structuring, .inserting:
            true
        case .idle, .completed, .error:
            false
        }
    }

    static func shouldUseTextPreview(mode: FloatingPanelDisplayMode) -> Bool {
        mode == .text
    }
}
