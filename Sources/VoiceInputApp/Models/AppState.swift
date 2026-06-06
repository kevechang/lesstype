public enum AppState: Equatable, Sendable {
    case idle
    case recording(AppMode)
    case recognizing(AppMode)
    case previewing(AppMode, text: String)
    case structuring(text: String)
    case inserting(text: String)
    case completed(text: String)
    case error(message: String)
}
