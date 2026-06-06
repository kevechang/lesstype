import SwiftUI

struct FloatingPreviewView: View {
    let state: AppState
    let stop: (() -> Void)?
    let cancel: () -> Void
    let showsTextPreview: Bool
    let asrStatus: String
    let actionHint: String

    init(
        state: AppState,
        stop: (() -> Void)?,
        cancel: @escaping () -> Void,
        showsTextPreview: Bool = true,
        asrStatus: String = "",
        actionHint: String = "Space 完成   放弃键放弃"
    ) {
        self.state = state
        self.stop = stop
        self.cancel = cancel
        self.showsTextPreview = showsTextPreview
        self.asrStatus = asrStatus
        self.actionHint = actionHint
    }

    var body: some View {
        switch FloatingPreviewPresentation.style(state: state, showsTextPreview: showsTextPreview) {
        case .capsule:
            capsuleBody
        case .textCard:
            textCardBody
        }
    }

    private var capsuleBody: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(capsuleTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(statusOnlyDetail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if stop != nil {
                Text(commitHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 252, height: 40, alignment: .leading)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var textCardBody: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(10)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isError {
                        Button(action: cancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.72))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭")
                    }
                }

                if shouldShowASRStatus {
                    Text(asrStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(asrStatusColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(actionHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: 396, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var capsuleTitle: String {
        switch state {
        case .previewing(let mode, _), .recording(let mode), .recognizing(let mode):
            mode.localizedName
        case .structuring:
            "自动分点"
        case .inserting:
            "正在输入"
        case .completed:
            "已完成"
        case .idle:
            "lesstype"
        case .error:
            "需要处理"
        }
    }

    private var detail: String {
        if !showsTextPreview {
            return statusOnlyDetail
        }

        return switch state {
        case .idle:
            "按快捷键开始语音输入"
        case .recording:
            "正在听..."
        case .recognizing:
            "正在把语音转换成文字。"
        case .previewing(_, let text):
            text.isEmpty ? "正在听..." : text
        case .structuring(let text), .inserting(let text), .completed(let text):
            text
        case .error(let message):
            message
        }
    }

    private var statusOnlyDetail: String {
        switch state {
        case .idle:
            "就绪"
        case .recording, .previewing:
            "正在听..."
        case .recognizing:
            "正在识别..."
        case .structuring:
            "正在分点..."
        case .inserting:
            "正在输入..."
        case .completed:
            "已完成"
        case .error(let message):
            message
        }
    }

    private var iconName: String {
        switch state {
        case .error:
            "exclamationmark.triangle.fill"
        case .structuring:
            "list.number"
        case .inserting:
            "text.cursor"
        case .recognizing:
            "waveform"
        default:
            "mic.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .error:
            .orange
        case .recording, .previewing:
            .accentColor
        default:
            .secondary
        }
    }

    private var shouldShowASRStatus: Bool {
        let trimmed = asrStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "未调用" else {
            return false
        }
        switch state {
        case .recognizing, .structuring, .inserting, .completed, .error:
            return true
        case .idle, .recording, .previewing:
            return trimmed.contains("失败") || trimmed.contains("已使用") || trimmed.contains("暂时不可用")
        }
    }

    private var asrStatusColor: Color {
        asrStatus.contains("失败") || asrStatus.contains("暂时不可用") ? .orange : .secondary
    }

    private var isError: Bool {
        if case .error = state {
            return true
        }
        return false
    }

    private var commitHint: String {
        actionHint
            .components(separatedBy: "   ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Space 完成"
    }
}

private extension AppMode {
    var localizedName: String {
        switch self {
        case .ordinary:
            "普通记录"
        case .structured:
            "自动分点"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
