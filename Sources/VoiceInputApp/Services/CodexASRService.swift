import Foundation
import Security
@preconcurrency import AVFoundation

public struct CodexASRCredentials: Codable, Equatable, Sendable {
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String
    public let accountID: String
    public let lastRefresh: String
    public let email: String
    public let type: String
    public let expired: String

    public init(
        idToken: String,
        accessToken: String,
        refreshToken: String,
        accountID: String,
        lastRefresh: String,
        email: String,
        type: String,
        expired: String
    ) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.lastRefresh = lastRefresh
        self.email = email
        self.type = type
        self.expired = expired
    }

    public static func imported(from data: Data) throws -> CodexASRCredentials {
        let credentials = try JSONDecoder().decode(CodexASRCredentials.self, from: data)
        guard credentials.type == "codex",
              !credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexASRError.invalidCredentials
        }
        return credentials
    }

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
        case lastRefresh = "last_refresh"
        case email
        case type
        case expired
    }
}

public protocol CodexASRCredentialStoring: Sendable {
    func loadCodexASRCredentials() -> CodexASRCredentials?
    func saveCodexASRCredentials(_ credentials: CodexASRCredentials)
    func deleteCodexASRCredentials()
}

public struct KeychainCodexASRCredentialStore: CodexASRCredentialStoring {
    private let service = "app.typeart.voiceinput"
    private let account = "codex-asr-credentials"

    public init() {}

    public func loadCodexASRCredentials() -> CodexASRCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(CodexASRCredentials.self, from: data)
    }

    public func saveCodexASRCredentials(_ credentials: CodexASRCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else {
            return
        }
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = baseQuery()
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    public func deleteCodexASRCredentials() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public protocol AudioTranscriptionServing: Sendable {
    func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String
}

public struct CodexASRUploadAudio: Sendable {
    public let url: URL
    public let removeAfterUpload: Bool

    public init(url: URL, removeAfterUpload: Bool = false) {
        self.url = url
        self.removeAfterUpload = removeAfterUpload
    }
}

public protocol CodexASRAudioPreparing: Sendable {
    func preparedAudio(for audioURL: URL) async -> CodexASRUploadAudio
}

public struct M4ACodexASRAudioPreparer: CodexASRAudioPreparing {
    public init() {}

    public func preparedAudio(for audioURL: URL) async -> CodexASRUploadAudio {
        guard audioURL.pathExtension.lowercased() != "m4a" else {
            return CodexASRUploadAudio(url: audioURL)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInput-upload-\(UUID().uuidString).m4a")
        do {
            try await Self.exportM4A(from: audioURL, to: outputURL)
            let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?
                .intValue ?? 0
            guard size > 0 else {
                try? FileManager.default.removeItem(at: outputURL)
                return CodexASRUploadAudio(url: audioURL)
            }
            return CodexASRUploadAudio(url: outputURL, removeAfterUpload: true)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            return CodexASRUploadAudio(url: audioURL)
        }
    }

    private static func exportM4A(from inputURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw CodexASRError.requestFailed
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true

        let exportSessionBox = AVAssetExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { continuation in
            exportSessionBox.session.exportAsynchronously {
                switch exportSessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    continuation.resume(throwing: exportSessionBox.session.error ?? CodexASRError.requestFailed)
                default:
                    continuation.resume(throwing: exportSessionBox.session.error ?? CodexASRError.requestFailed)
                }
            }
        }
    }
}

private final class AVAssetExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

public struct CodexASRTranscriptionService: AudioTranscriptionServing {
    private let credentialStore: CodexASRCredentialStoring
    private let session: URLSession
    private let endpoint: URL
    private let audioPreparer: any CodexASRAudioPreparing

    public init(
        credentialStore: CodexASRCredentialStoring = KeychainCodexASRCredentialStore(),
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/transcribe")!,
        audioPreparer: any CodexASRAudioPreparing = M4ACodexASRAudioPreparer()
    ) {
        self.credentialStore = credentialStore
        self.session = session
        self.endpoint = endpoint
        self.audioPreparer = audioPreparer
    }

    public func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        guard let credentials = credentialStore.loadCodexASRCredentials() else {
            throw CodexASRError.missingCredentials
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "Chatgpt-Account-Id")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let uploadAudio = await audioPreparer.preparedAudio(for: audioURL)
        defer {
            if uploadAudio.removeAfterUpload {
                try? FileManager.default.removeItem(at: uploadAudio.url)
            }
        }
        let body = try multipartBody(audioURL: uploadAudio.url, languageMode: languageMode, request: &request)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexASRError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexASRError.httpError(
                statusCode: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }

        if let decoded = try? JSONDecoder().decode(CodexASRTextResponse.self, from: data) {
            let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw CodexASRError.emptyResponse
            }
            return text
        }

        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CodexASRError.emptyResponse
        }
        return text
    }

    private func multipartBody(audioURL: URL, languageMode: LanguageMode, request: inout URLRequest) throws -> Data {
        let boundary = "VoiceInputCodexASR-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(name: "language", value: languageCode(for: languageMode), boundary: boundary)
        body.appendFileField(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: mimeType(for: audioURL),
            data: try Data(contentsOf: audioURL),
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func languageCode(for languageMode: LanguageMode) -> String {
        switch languageMode {
        case .chineseFirst:
            "zh"
        case .englishFirst:
            "en"
        case .automatic:
            "auto"
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a":
            "audio/mp4"
        case "wav":
            "audio/wav"
        case "caf":
            "audio/x-caf"
        default:
            "application/octet-stream"
        }
    }

    private static var userAgent: String {
        "Codex Desktop/26.429.30905 (macOS; \(archName))"
    }

    private static var archName: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

public struct CodexASRFinalTranscriptionService: Sendable {
    private let transcription: AudioTranscriptionServing
    private let postProcessor: TextPostProcessor
    private let timeout: Duration
    private let reportStatus: @MainActor @Sendable (String) -> Void
    private let recordUsage: @MainActor @Sendable (CodexASRUsageOutcome) -> Void

    public init(
        transcription: AudioTranscriptionServing = CodexASRTranscriptionService(),
        postProcessor: TextPostProcessor = TextPostProcessor(),
        timeout: Duration = .seconds(60),
        reportStatus: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        recordUsage: @escaping @MainActor @Sendable (CodexASRUsageOutcome) -> Void = { _ in }
    ) {
        self.transcription = transcription
        self.postProcessor = postProcessor
        self.timeout = timeout
        self.reportStatus = reportStatus
        self.recordUsage = recordUsage
    }

    public func resolvedText(from result: RecognitionResult, preferences: Preferences) async -> String {
        guard preferences.cloudTranscriptionEnabled else {
            return result.finalText
        }
        guard let audioURL = result.audioURL else {
            await reportStatus("Codex ASR 未拿到录音文件，已使用 Apple 识别结果")
            return result.finalText
        }

        do {
            await reportStatus(Self.transcribingStatus(audioURL: audioURL, timeout: timeout))
            let text = TextPostProcessor.simplifiedChinese(
                try await transcribeWithTimeout(audioURL: audioURL, languageMode: preferences.languageMode)
            )
            await recordUsage(.success)
            await reportStatus("Codex ASR 已使用 \(Self.timestamp())")
            guard preferences.chinesePunctuationEnabled == false else {
                return text
            }
            return postProcessor.process(text, preferences: preferences)
        } catch CodexASRError.timeout {
            await recordUsage(.timeout)
            await reportStatus("Codex ASR 超时，已使用 Apple 识别结果")
            return result.finalText
        } catch {
            if Self.isQuotaLimited(error) {
                await recordUsage(.quotaLimited)
                await reportStatus("Codex ASR 暂时不可用，已改用 Apple 识别。可能是账号额度或频率限制，稍后再试即可。")
                return result.finalText
            }
            await recordUsage(.failure)
            await reportStatus("Codex ASR 转写失败：\(error.localizedDescription)，已使用 Apple 识别结果")
            return result.finalText
        }
    }

    private func transcribeWithTimeout(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        let transcriptionTask = Task {
            try await transcription.transcribe(audioURL: audioURL, languageMode: languageMode)
        }
        let timeoutTask = Task<String, Error> {
            try await Task.sleep(for: timeout)
            throw CodexASRError.timeout
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = OneShotFlag()

                Task {
                    do {
                        let value = try await transcriptionTask.value
                        if state.claim() {
                            timeoutTask.cancel()
                            continuation.resume(returning: value)
                        }
                    } catch {
                        if state.claim() {
                            timeoutTask.cancel()
                            continuation.resume(throwing: error)
                        }
                    }
                }

                Task {
                    do {
                        let value = try await timeoutTask.value
                        if state.claim() {
                            transcriptionTask.cancel()
                            continuation.resume(returning: value)
                        }
                    } catch {
                        if state.claim() {
                            transcriptionTask.cancel()
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            transcriptionTask.cancel()
            timeoutTask.cancel()
        }
    }

    private final class OneShotFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.withLock {
                guard !claimed else {
                    return false
                }
                claimed = true
                return true
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func transcribingStatus(audioURL: URL, timeout: Duration) -> String {
        "Codex ASR 转写中... 最长等待 \(timeoutSeconds(timeout)) 秒 / 文件大小 \(fileSizeMegabytes(audioURL)) MB"
    }

    private static func timeoutSeconds(_ timeout: Duration) -> Int64 {
        let components = timeout.components
        if components.attoseconds > 0 {
            return components.seconds + 1
        }
        return components.seconds
    }

    private static func fileSizeMegabytes(_ url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .doubleValue ?? 0
        return String(format: "%.2f", size / 1_048_576)
    }

    private static func isQuotaLimited(_ error: Error) -> Bool {
        guard case let CodexASRError.httpError(statusCode, body) = error else {
            return false
        }
        if statusCode == 429 || statusCode == 403 {
            return true
        }
        let lowercasedBody = body.lowercased()
        return lowercasedBody.contains("quota")
            || lowercasedBody.contains("limit")
            || lowercasedBody.contains("rate limit")
            || lowercasedBody.contains("usage")
    }
}

public enum CodexASRError: LocalizedError, Equatable {
    case invalidCredentials
    case missingCredentials
    case requestFailed
    case httpError(statusCode: Int, body: String)
    case emptyResponse
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "CPA 账号 JSON 无效。"
        case .missingCredentials:
            "尚未导入 Codex ASR 账号。"
        case .requestFailed:
            "Codex ASR 请求失败。"
        case .httpError(let statusCode, _):
            "Codex ASR 返回 HTTP \(statusCode)。"
        case .emptyResponse:
            "Codex ASR 没有返回文本。"
        case .timeout:
            "Codex ASR 请求超时。"
        }
    }
}

private struct CodexASRTextResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFileField(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}
