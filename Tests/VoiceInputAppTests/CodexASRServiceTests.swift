import XCTest
@testable import VoiceInputApp

final class CodexASRServiceTests: XCTestCase {
    func testImportsCPAJSONAndStoresSecretsOutsideUserDefaults() throws {
        let credentials = try CodexASRCredentials.imported(from: Self.cpaJSON)

        XCTAssertEqual(credentials.email, "user@example.com")
        XCTAssertEqual(credentials.type, "codex")
        XCTAssertEqual(credentials.accessToken, "dummy-access-token")
        XCTAssertEqual(credentials.refreshToken, "dummy-refresh-token")
        XCTAssertEqual(credentials.accountID, "dummy-account-id")
    }

    @MainActor
    func testPreferencesStoreImportsCodexASRAccountWithoutPersistingTokensInUserDefaults() throws {
        let suiteName = "CodexASRServiceTests.preferences"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let codexStore = InMemoryCodexASRCredentialStore()
        let store = PreferencesStore(
            defaults: defaults,
            apiKeyStore: InMemoryCodexASRAPIKeyStore(),
            codexASRCredentialStore: codexStore
        )

        try store.importCodexASRCredentials(from: Self.cpaJSON)

        let storedData = try XCTUnwrap(defaults.data(forKey: "preferences"))
        let storedJSON = String(decoding: storedData, as: UTF8.self)
        XCTAssertFalse(storedJSON.contains("dummy-access-token"))
        XCTAssertFalse(storedJSON.contains("dummy-refresh-token"))
        XCTAssertEqual(store.preferences.codexASREmail, "user@example.com")
        XCTAssertEqual(codexStore.credentials?.accessToken, "dummy-access-token")
    }

    func testTranscriptionRequestUsesCodexHeadersAndParsesText() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let credentialStore = InMemoryCodexASRCredentialStore()
        credentialStore.credentials = CodexASRCredentials(
            idToken: "dummy-id-token",
            accessToken: "dummy-access-token",
            refreshToken: "dummy-refresh-token",
            accountID: "dummy-account-id",
            lastRefresh: "2026-05-10T10:00:00Z",
            email: "user@example.com",
            type: "codex",
            expired: "2999-01-01T00:00:00Z"
        )
        let service = CodexASRTranscriptionService(
            credentialStore: credentialStore,
            session: Self.mockedSession { request in
                XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/transcribe")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.timeoutInterval, 60)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dummy-access-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Chatgpt-Account-Id"), "dummy-account-id")
                XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "Codex Desktop")
                XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Codex Desktop/") == true)
                XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
                return Self.response(body: #"{"text":"Codex 转写结果"}"#, url: request.url)
            }
        )

        let result = try await service.transcribe(audioURL: audioURL, languageMode: .chineseFirst)

        XCTAssertEqual(result, "Codex 转写结果")
    }

    func testTranscriptionRequestUsesWAVUploadMetadataForSupportedAudio() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("RIFF....WAVEfmt ".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let credentialStore = InMemoryCodexASRCredentialStore()
        credentialStore.credentials = Self.testCredentials
        let service = CodexASRTranscriptionService(
            credentialStore: credentialStore,
            session: Self.mockedSession { request in
                let body = try XCTUnwrap(Self.requestBodyData(from: request))
                let bodyText = String(decoding: body, as: UTF8.self)
                XCTAssertTrue(bodyText.contains(#"filename="\#(audioURL.lastPathComponent)""#))
                XCTAssertTrue(bodyText.contains("Content-Type: audio/wav"))
                return Self.response(body: #"{"text":"Codex 转写结果"}"#, url: request.url)
            }
        )

        _ = try await service.transcribe(audioURL: audioURL, languageMode: .chineseFirst)
    }

    func testFinalTranscriptionReplacesASRPunctuationWithSpacesWhenPunctuationDisabled() async throws {
        var preferences = Preferences.defaults
        preferences.cloudTranscriptionEnabled = true
        preferences.chinesePunctuationEnabled = false
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let service = CodexASRFinalTranscriptionService(
            transcription: StaticAudioTranscriptionService(text: "我已经调用 ASR 了，然后继续输入。")
        )

        let result = await service.resolvedText(
            from: RecognitionResult(finalText: "Apple 结果", previews: [], audioURL: audioURL),
            preferences: preferences
        )

        XCTAssertEqual(result, "我已经调用 ASR 了  然后继续输入")
    }

    func testFinalTranscriptionConvertsASRResultToSimplifiedChineseWhenPunctuationEnabled() async throws {
        var preferences = Preferences.defaults
        preferences.cloudTranscriptionEnabled = true
        preferences.chinesePunctuationEnabled = true
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let service = CodexASRFinalTranscriptionService(
            transcription: StaticAudioTranscriptionService(text: "這個語音識別軟體輸出繁體中文。")
        )

        let result = await service.resolvedText(
            from: RecognitionResult(finalText: "Apple 结果", previews: [], audioURL: audioURL),
            preferences: preferences
        )

        XCTAssertEqual(result, "这个语音识别软体输出繁体中文。")
    }

    @MainActor
    func testFinalTranscriptionReportsVisibleASRStatus() async throws {
        var preferences = Preferences.defaults
        preferences.cloudTranscriptionEnabled = true
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        var statuses: [String] = []
        let service = CodexASRFinalTranscriptionService(
            transcription: StaticAudioTranscriptionService(text: "Codex ASR 结果"),
            reportStatus: { status in
                statuses.append(status)
            }
        )

        _ = await service.resolvedText(
            from: RecognitionResult(finalText: "Apple 结果", previews: [], audioURL: audioURL),
            preferences: preferences
        )

        XCTAssertTrue(statuses.contains { $0.hasPrefix("Codex ASR 转写中...") })
        XCTAssertTrue(statuses.contains { $0.hasPrefix("Codex ASR 已使用") })
    }

    @MainActor
    func testFinalTranscriptionReportsDefaultWaitAndAudioFileSize() async throws {
        var preferences = Preferences.defaults
        preferences.cloudTranscriptionEnabled = true
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 1_048_576).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        var statuses: [String] = []
        let service = CodexASRFinalTranscriptionService(
            transcription: StaticAudioTranscriptionService(text: "Codex ASR 结果"),
            reportStatus: { status in
                statuses.append(status)
            }
        )

        _ = await service.resolvedText(
            from: RecognitionResult(finalText: "Apple 结果", previews: [], audioURL: audioURL),
            preferences: preferences
        )

        XCTAssertTrue(statuses.contains("Codex ASR 转写中... 最长等待 60 秒 / 文件大小 1.00 MB"))
    }

    @MainActor
    func testFinalTranscriptionFallsBackWhenASRTimesOut() async throws {
        var preferences = Preferences.defaults
        preferences.cloudTranscriptionEnabled = true
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        var statuses: [String] = []
        let service = CodexASRFinalTranscriptionService(
            transcription: SlowAudioTranscriptionService(),
            timeout: .milliseconds(5),
            reportStatus: { status in
                statuses.append(status)
            }
        )

        let result = await service.resolvedText(
            from: RecognitionResult(finalText: "Apple 结果", previews: [], audioURL: audioURL),
            preferences: preferences
        )

        XCTAssertEqual(result, "Apple 结果")
        XCTAssertTrue(statuses.contains { $0.contains("超时") && $0.contains("Apple") })
    }

    @MainActor
    func testFinalTranscriptionReportsGentleQuotaReminderAndRecordsLimitedUsage() async throws {
        var preferences = Preferences.defaults
        preferences.cloudTranscriptionEnabled = true
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexASRServiceTests-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        var statuses: [String] = []
        var outcomes: [CodexASRUsageOutcome] = []
        let service = CodexASRFinalTranscriptionService(
            transcription: FailingAudioTranscriptionService(
                error: CodexASRError.httpError(statusCode: 429, body: "usage limit reached")
            ),
            reportStatus: { status in
                statuses.append(status)
            },
            recordUsage: { outcome in
                outcomes.append(outcome)
            }
        )

        let result = await service.resolvedText(
            from: RecognitionResult(finalText: "Apple 结果", previews: [], audioURL: audioURL),
            preferences: preferences
        )

        XCTAssertEqual(result, "Apple 结果")
        XCTAssertEqual(outcomes, [.quotaLimited])
        XCTAssertTrue(statuses.contains("Codex ASR 暂时不可用，已改用 Apple 识别。可能是账号额度或频率限制，稍后再试即可。"))
    }

    private static let cpaJSON = Data("""
    {
      "id_token": "dummy-id-token",
      "access_token": "dummy-access-token",
      "refresh_token": "dummy-refresh-token",
      "account_id": "dummy-account-id",
      "last_refresh": "2026-05-10T10:00:00Z",
      "email": "user@example.com",
      "type": "codex",
      "expired": "2999-01-01T00:00:00Z"
    }
    """.utf8)

    private static let testCredentials = CodexASRCredentials(
        idToken: "dummy-id-token",
        accessToken: "dummy-access-token",
        refreshToken: "dummy-refresh-token",
        accountID: "dummy-account-id",
        lastRefresh: "2026-05-10T10:00:00Z",
        email: "user@example.com",
        type: "codex",
        expired: "2999-01-01T00:00:00Z"
    )

    private static func mockedSession(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        CodexASRMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexASRMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(body: String, url: URL?) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            body.data(using: .utf8)!
        )
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class CodexASRMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class InMemoryCodexASRCredentialStore: CodexASRCredentialStoring, @unchecked Sendable {
    var credentials: CodexASRCredentials?

    func loadCodexASRCredentials() -> CodexASRCredentials? {
        credentials
    }

    func saveCodexASRCredentials(_ credentials: CodexASRCredentials) {
        self.credentials = credentials
    }

    func deleteCodexASRCredentials() {
        credentials = nil
    }
}

private final class InMemoryCodexASRAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    func loadAPIKey() -> String { "" }
    func saveAPIKey(_ apiKey: String) {}
    func loadAPIKey(for scope: ModelConfigurationScope) -> String { "" }
    func saveAPIKey(_ apiKey: String, for scope: ModelConfigurationScope) {}
}

private struct StaticAudioTranscriptionService: AudioTranscriptionServing {
    let text: String

    func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        text
    }
}

private struct SlowAudioTranscriptionService: AudioTranscriptionServing {
    func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        try await Task.sleep(for: .seconds(60))
        return "太晚了"
    }
}

private struct FailingAudioTranscriptionService: AudioTranscriptionServing {
    let error: Error

    func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        throw error
    }
}
