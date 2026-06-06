public enum VoiceInputSettingsSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case shortcuts
    case recognition
    case models
    case phrases
    case prompts
    case floatingPanel
    case diagnostics
    case history

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .overview:
            "总览"
        case .shortcuts:
            "快捷键"
        case .recognition:
            "识别与 ASR"
        case .models:
            "大模型"
        case .phrases:
            "高频词组"
        case .prompts:
            "提示词"
        case .floatingPanel:
            "浮窗"
        case .diagnostics:
            "诊断"
        case .history:
            "最近输入"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview:
            "gauge.with.dots.needle.67percent"
        case .shortcuts:
            "keyboard"
        case .recognition:
            "waveform"
        case .models:
            "sparkles"
        case .phrases:
            "text.book.closed"
        case .prompts:
            "text.alignleft"
        case .floatingPanel:
            "rectangle.on.rectangle"
        case .diagnostics:
            "stethoscope"
        case .history:
            "clock.arrow.circlepath"
        }
    }
}
