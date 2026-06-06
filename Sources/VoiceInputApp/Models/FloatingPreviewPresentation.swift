enum FloatingPreviewPresentation: Equatable {
    case capsule
    case textCard

    static func style(state: AppState, showsTextPreview: Bool) -> FloatingPreviewPresentation {
        if case .error = state {
            return .textCard
        }

        return showsTextPreview ? .textCard : .capsule
    }
}
