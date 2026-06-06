import Foundation

public protocol ModelProviding: Sendable {
    func structureNotes(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, promptStyle: NoteStructuringPromptStyle, instructions: String) async throws -> String
    func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String
}

public enum NoteStructuringPromptStyle: Equatable, Sendable {
    case polishedNotes
    case preserveOriginalText

    var instructions: String {
        switch self {
        case .polishedNotes:
            ModelPromptDefaults.polishedStructuring
        case .preserveOriginalText:
            ModelPromptDefaults.preserveOriginalStructuring
        }
    }
}

public protocol OpenAIConfigurationResolving: Sendable {
    func resolvedAPIKey(preferences: Preferences) -> String
    func resolvedAPIKey(preferences: Preferences, scope: ModelConfigurationScope) -> String
    func resolvedModel(preferences: Preferences) -> String
    func resolvedModel(preferences: Preferences, scope: ModelConfigurationScope) -> String
    func resolvedAPIURL(preferences: Preferences) -> URL
    func resolvedAPIURL(preferences: Preferences, scope: ModelConfigurationScope) -> URL
    func resolvedAPIStyle(preferences: Preferences) -> ModelAPIStyle
    func resolvedAPIStyle(preferences: Preferences, scope: ModelConfigurationScope) -> ModelAPIStyle
}

public extension OpenAIConfigurationResolving {
    func resolvedAPIKey(preferences: Preferences, scope: ModelConfigurationScope) -> String {
        resolvedAPIKey(preferences: preferences)
    }

    func resolvedModel(preferences: Preferences, scope: ModelConfigurationScope) -> String {
        resolvedModel(preferences: preferences)
    }

    func resolvedAPIURL(preferences: Preferences, scope: ModelConfigurationScope) -> URL {
        resolvedAPIURL(preferences: preferences)
    }

    func resolvedAPIStyle(preferences: Preferences, scope: ModelConfigurationScope) -> ModelAPIStyle {
        resolvedAPIStyle(preferences: preferences)
    }
}

public struct CodexOpenAIConfigurationResolver: OpenAIConfigurationResolving {
    private let environment: [String: String]
    private let codexHome: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) {
        self.environment = environment
        self.codexHome = codexHome
    }

    public func resolvedAPIKey(preferences: Preferences) -> String {
        resolvedAPIKey(preferences: preferences, scope: .structured)
    }

    public func resolvedAPIKey(preferences: Preferences, scope: ModelConfigurationScope) -> String {
        let explicitKey = preferences.apiKey(for: scope).trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitKey.isEmpty {
            return explicitKey
        }

        if let environmentKey = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentKey.isEmpty {
            return environmentKey
        }

        return codexAuthAPIKey()
    }

    public func resolvedModel(preferences: Preferences) -> String {
        resolvedModel(preferences: preferences, scope: .structured)
    }

    public func resolvedModel(preferences: Preferences, scope: ModelConfigurationScope) -> String {
        let explicitModel = preferences.modelName(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitModel.isEmpty {
            return explicitModel
        }

        return codexConfiguredModel() ?? "gpt-4.1-mini"
    }

    public func resolvedAPIURL(preferences: Preferences) -> URL {
        resolvedAPIURL(preferences: preferences, scope: .structured)
    }

    public func resolvedAPIURL(preferences: Preferences, scope: ModelConfigurationScope) -> URL {
        let apiStyle = resolvedAPIStyle(preferences: preferences, scope: scope)
        let explicitURL = preferences.apiURL(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: explicitURL),
           !explicitURL.isEmpty,
           !Self.isBuiltInDefaultEndpoint(url) {
            return Self.endpointURL(from: url, apiStyle: apiStyle)
        }
        return apiStyle.defaultAPIURL
    }

    public func resolvedAPIStyle(preferences: Preferences) -> ModelAPIStyle {
        resolvedAPIStyle(preferences: preferences, scope: .structured)
    }

    public func resolvedAPIStyle(preferences: Preferences, scope: ModelConfigurationScope) -> ModelAPIStyle {
        preferences.modelAPIStyle(for: scope) ?? .codexCLI
    }

    private func codexAuthAPIKey() -> String {
        let authURL = codexHome.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["OPENAI_API_KEY"] as? String else {
            return ""
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func codexConfiguredModel() -> String? {
        let configURL = codexHome.appendingPathComponent("config.toml")
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }
        guard let match = config.firstMatch(of: /^model\s*=\s*"([^"]+)"/) else {
            return nil
        }
        return String(match.1)
    }

    private static func isBuiltInDefaultEndpoint(_ url: URL) -> Bool {
        let absoluteString = url.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return ModelAPIStyle.allCases.contains {
            $0.defaultAPIURL.absoluteString
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased() == absoluteString
        }
    }

    private static func endpointURL(from url: URL, apiStyle: ModelAPIStyle) -> URL {
        guard apiStyle != .codexCLI else {
            return url
        }
        let endpoint = apiStyle.endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.lowercased().hasSuffix(endpoint.lowercased()) {
            return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let prefix = normalizedPath.isEmpty ? defaultPathPrefix(for: url, apiStyle: apiStyle) : normalizedPath
        components?.path = "/" + [prefix, endpoint]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return components?.url ?? url
    }

    private static func defaultPathPrefix(for url: URL, apiStyle: ModelAPIStyle) -> String {
        switch apiStyle {
        case .openAIResponses, .openAICompatibleChat:
            return url.host?.localizedCaseInsensitiveCompare("api.openai.com") == .orderedSame ? "v1" : ""
        case .anthropicMessages:
            return "v1"
        case .codexCLI:
            return ""
        }
    }
}

public struct OpenAIModelProvider: ModelProviding {
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession
    private let cache: ModelResponseCache

    public init(session: URLSession = OpenAIModelProvider.defaultSession, cache: ModelResponseCache = ModelResponseCache()) {
        self.session = session
        self.cache = cache
    }

    public func structureNotes(
        text: String,
        apiKey: String,
        model: String,
        apiURL: URL,
        apiStyle: ModelAPIStyle,
        promptStyle: NoteStructuringPromptStyle = .polishedNotes
    ) async throws -> String {
        try await structureNotes(
            text: text,
            apiKey: apiKey,
            model: model,
            apiURL: apiURL,
            apiStyle: apiStyle,
            promptStyle: promptStyle,
            instructions: promptStyle.instructions
        )
    }

    public func structureNotes(
        text: String,
        apiKey: String,
        model: String,
        apiURL: URL,
        apiStyle: ModelAPIStyle,
        promptStyle: NoteStructuringPromptStyle = .polishedNotes,
        instructions: String
    ) async throws -> String {
        guard apiStyle != .codexCLI else {
            throw ModelProviderError.requestFailed
        }
        return try await requestText(
            text: text,
            apiKey: apiKey,
            model: model,
            apiURL: apiURL,
            apiStyle: apiStyle,
            instructions: instructions
        )
    }

    public func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle) async throws -> String {
        try await enhanceText(
            text: text,
            apiKey: apiKey,
            model: model,
            apiURL: apiURL,
            apiStyle: apiStyle,
            instructions: ModelPromptDefaults.ordinaryEnhancement
        )
    }

    public func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        guard apiStyle != .codexCLI else {
            throw ModelProviderError.requestFailed
        }
        return try await requestText(
            text: text,
            apiKey: apiKey,
            model: model,
            apiURL: apiURL,
            apiStyle: apiStyle,
            instructions: instructions
        )
    }

    public func streamText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        guard apiStyle != .codexCLI else {
            throw ModelProviderError.requestFailed
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body = requestBody(text: text, apiKey: apiKey, model: model, apiStyle: apiStyle, instructions: instructions, request: &request)
        body["stream"] = true
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelProviderError.httpError(statusCode: http.statusCode, body: Self.responseBody(from: data))
        }
        let parsed = try ServerSentEventTextParser().parse(data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.isEmpty else {
            throw ModelProviderError.emptyResponse
        }
        return parsed
    }

    private func requestText(
        text: String,
        apiKey: String,
        model: String,
        apiURL: URL,
        apiStyle: ModelAPIStyle,
        instructions: String
    ) async throws -> String {
        let cacheKey = ModelResponseCacheKey(
            text: text,
            model: model,
            apiURL: apiURL,
            apiStyle: apiStyle,
            instructions: instructions
        )
        if let cached = await cache.value(for: cacheKey) {
            return cached
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = requestBody(text: text, apiKey: apiKey, model: model, apiStyle: apiStyle, instructions: instructions, request: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelProviderError.httpError(statusCode: http.statusCode, body: Self.responseBody(from: data))
        }

        do {
            switch apiStyle {
            case .codexCLI:
                throw ModelProviderError.requestFailed
            case .openAIResponses:
                let decoded = try JSONDecoder().decode(ResponsesAPITextResponse.self, from: data)
                let output = try decoded.validatedOutputText()
                await cache.set(output, for: cacheKey)
                return output
            case .openAICompatibleChat:
                let decoded = try JSONDecoder().decode(ChatCompletionsTextResponse.self, from: data)
                let output = try decoded.validatedOutputText()
                await cache.set(output, for: cacheKey)
                return output
            case .anthropicMessages:
                let decoded = try JSONDecoder().decode(AnthropicMessagesTextResponse.self, from: data)
                let output = try decoded.validatedOutputText()
                await cache.set(output, for: cacheKey)
                return output
            }
        } catch let error as ModelProviderError {
            throw error
        } catch {
            throw ModelProviderError.responseParsingFailed(body: Self.responseBody(from: data), reason: error.localizedDescription)
        }
    }

    private func requestBody(
        text: String,
        apiKey: String,
        model: String,
        apiStyle: ModelAPIStyle,
        instructions: String,
        request: inout URLRequest
    ) -> [String: Any] {
        switch apiStyle {
        case .codexCLI:
            return [:]
        case .openAIResponses:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return [
                "model": model,
                "input": "\(instructions)\n\n\(text)"
            ]
        case .openAICompatibleChat:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return [
                "model": model,
                "messages": [
                    ["role": "system", "content": instructions],
                    ["role": "user", "content": text]
                ]
            ]
        case .anthropicMessages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return [
                "model": model,
                "max_tokens": 1024,
                "system": instructions,
                "messages": [
                    ["role": "user", "content": text]
                ]
            ]
        }
    }

    private static func responseBody(from data: Data) -> String {
        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard body.count > 800 else {
            return body
        }
        return String(body.prefix(800)) + "..."
    }
}

public struct ModelResponseCacheKey: Hashable, Sendable {
    public let text: String
    public let model: String
    public let apiURL: URL
    public let apiStyle: ModelAPIStyle
    public let instructions: String

    public init(text: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) {
        self.text = text
        self.model = model
        self.apiURL = apiURL
        self.apiStyle = apiStyle
        self.instructions = instructions
    }
}

public actor ModelResponseCache {
    public static let shared = ModelResponseCache()

    private let ttl: TimeInterval
    private let limit: Int
    private var storage: [ModelResponseCacheKey: (value: String, expiresAt: Date)] = [:]

    public init(ttl: TimeInterval = 300, limit: Int = 80) {
        self.ttl = ttl
        self.limit = max(1, limit)
    }

    public func value(for key: ModelResponseCacheKey, now: Date = Date()) -> String? {
        guard let entry = storage[key] else {
            return nil
        }
        guard entry.expiresAt > now else {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    public func set(_ value: String, for key: ModelResponseCacheKey, now: Date = Date()) {
        storage[key] = (value, now.addingTimeInterval(ttl))
        trimIfNeeded()
    }

    public func removeAll() {
        storage.removeAll()
    }

    private func trimIfNeeded() {
        guard storage.count > limit else {
            return
        }
        let overflow = storage.count - limit
        let keysToRemove = storage
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        for key in keysToRemove {
            storage.removeValue(forKey: key)
        }
    }
}

public struct HybridModelProvider: ModelProviding {
    private let codex: ModelProviding
    private let api: ModelProviding

    public init(codex: ModelProviding = CodexCLIModelProvider(), api: ModelProviding = OpenAIModelProvider()) {
        self.codex = codex
        self.api = api
    }

    public func structureNotes(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, promptStyle: NoteStructuringPromptStyle, instructions: String) async throws -> String {
        switch apiStyle {
        case .codexCLI:
            return try await codex.structureNotes(text: text, apiKey: apiKey, model: model, apiURL: apiURL, apiStyle: apiStyle, promptStyle: promptStyle, instructions: instructions)
        case .openAIResponses, .openAICompatibleChat, .anthropicMessages:
            return try await api.structureNotes(text: text, apiKey: apiKey, model: model, apiURL: apiURL, apiStyle: apiStyle, promptStyle: promptStyle, instructions: instructions)
        }
    }

    public func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        switch apiStyle {
        case .codexCLI:
            return try await codex.enhanceText(text: text, apiKey: apiKey, model: model, apiURL: apiURL, apiStyle: apiStyle, instructions: instructions)
        case .openAIResponses, .openAICompatibleChat, .anthropicMessages:
            return try await api.enhanceText(text: text, apiKey: apiKey, model: model, apiURL: apiURL, apiStyle: apiStyle, instructions: instructions)
        }
    }
}

public struct CodexCLIModelProvider: ModelProviding {
    private let executableCandidates: [URL]

    public init(
        executableCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
    ) {
        self.executableCandidates = executableCandidates
    }

    public func structureNotes(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, promptStyle: NoteStructuringPromptStyle, instructions: String) async throws -> String {
        try await runCodex(
            prompt: """
            \(instructions)
            只输出最终文本。

            \(text)
            """
        )
    }

    public func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle) async throws -> String {
        try await enhanceText(
            text: text,
            apiKey: apiKey,
            model: model,
            apiURL: apiURL,
            apiStyle: apiStyle,
            instructions: ModelPromptDefaults.ordinaryEnhancement
        )
    }

    public func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        try await runCodex(
            prompt: """
            \(instructions)

            \(text)
            """
        )
    }

    private func runCodex(prompt: String) async throws -> String {
        guard let executableURL = executableCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ModelProviderError.codexUnavailable("找不到 codex 命令")
        }

        return try await Task.detached(priority: .userInitiated) {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("voiceinput-codex-\(UUID().uuidString).txt")
            defer {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let process = Process()
            process.executableURL = executableURL
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.arguments = [
                "exec",
                "--skip-git-repo-check",
                "--sandbox",
                "read-only",
                "--ephemeral",
                "--output-last-message",
                outputURL.path,
                prompt
            ]
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"],
                uniquingKeysWith: { _, new in new }
            )
            process.standardInput = FileHandle.nullDevice
            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ModelProviderError.codexUnavailable(message?.isEmpty == false ? message! : "codex exec 失败")
            }

            let output = try String(contentsOf: outputURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                throw ModelProviderError.emptyResponse
            }
            return output
        }.value
    }
}

public protocol TextEnhancementService: Sendable {
    func enhance(_ text: String, preferences: Preferences) async throws -> String
}

public struct ModelBackedTextEnhancementService: TextEnhancementService {
    private let local: TextPostProcessor
    private let provider: ModelProviding
    private let configurationResolver: OpenAIConfigurationResolving
    private let phraseCorrection: PhraseCorrectionService
    private let reportStatus: @MainActor @Sendable (String) -> Void

    public init(
        local: TextPostProcessor = TextPostProcessor(),
        provider: ModelProviding,
        configurationResolver: OpenAIConfigurationResolving = CodexOpenAIConfigurationResolver(),
        phraseCorrection: PhraseCorrectionService = PhraseCorrectionService(),
        reportStatus: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) {
        self.local = local
        self.provider = provider
        self.configurationResolver = configurationResolver
        self.phraseCorrection = phraseCorrection
        self.reportStatus = reportStatus
    }

    public func enhance(_ text: String, preferences: Preferences) async throws -> String {
        let fallback = local.process(text, preferences: preferences)
        guard preferences.ordinaryModelEnhancementEnabled == true else {
            await reportStatus("大模型未开启，普通模式已使用本地处理")
            return fallback
        }

        let scope = ModelConfigurationScope.ordinary
        let apiStyle = configurationResolver.resolvedAPIStyle(preferences: preferences, scope: scope)
        let apiKey = configurationResolver.resolvedAPIKey(preferences: preferences, scope: scope)
        if apiStyle != .codexCLI, apiKey.isEmpty {
            await reportStatus("未找到 API Key，普通模式已使用本地处理")
            return fallback
        }

        do {
            let model = configurationResolver.resolvedModel(preferences: preferences, scope: scope)
            let apiURL = configurationResolver.resolvedAPIURL(preferences: preferences, scope: scope)
            guard isModelReady(model, apiStyle: apiStyle, apiURL: apiURL, preferences: preferences, scope: scope) else {
                await reportStatus("第三方兼容接口需要填写模型名称，普通模式已使用本地处理")
                return fallback
            }
            await reportStatus("正在增强普通文本：\(apiStyle.displayName)")
            return try await provider.enhanceText(
                text: text,
                apiKey: apiKey,
                model: model,
                apiURL: apiURL,
                apiStyle: apiStyle,
                instructions: instructionsWithPhraseGlossary(preferences.resolvedOrdinaryEnhancementPrompt, preferences: preferences)
            )
        } catch {
            await reportStatus("普通模式大模型失败：\(error.localizedDescription)")
            return fallback
        }
    }

    private func instructionsWithPhraseGlossary(_ base: String, preferences: Preferences) -> String {
        guard let glossary = phraseCorrection.promptGlossary(from: preferences) else {
            return base
        }
        return base + glossary
    }

    private func isModelReady(_ model: String, apiStyle: ModelAPIStyle, apiURL: URL, preferences: Preferences, scope: ModelConfigurationScope) -> Bool {
        if apiStyle == .anthropicMessages {
            return preferences.modelName(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard apiStyle == .openAICompatibleChat else {
            return true
        }
        let explicitModel = preferences.modelName(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitModel.isEmpty {
            return true
        }
        return apiURL.host?.localizedCaseInsensitiveContains("openai.com") == true && !model.isEmpty
    }
}

public struct CloudOrLocalNoteStructuringService: NoteStructuringService {
    private let local: NoteStructuringService
    private let provider: ModelProviding
    private let configurationResolver: OpenAIConfigurationResolving
    private let phraseCorrection: PhraseCorrectionService
    private let reportStatus: @MainActor @Sendable (String) -> Void

    public init(
        local: NoteStructuringService,
        provider: ModelProviding,
        configurationResolver: OpenAIConfigurationResolving = CodexOpenAIConfigurationResolver(),
        phraseCorrection: PhraseCorrectionService = PhraseCorrectionService(),
        reportStatus: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) {
        self.local = local
        self.provider = provider
        self.configurationResolver = configurationResolver
        self.phraseCorrection = phraseCorrection
        self.reportStatus = reportStatus
    }

    public func structure(_ text: String, preferences: Preferences) async throws -> String {
        let scope = ModelConfigurationScope.structured
        let apiStyle = configurationResolver.resolvedAPIStyle(preferences: preferences, scope: scope)
        let apiKey = configurationResolver.resolvedAPIKey(preferences: preferences, scope: scope)
        guard preferences.cloudEnhancementEnabled else {
            await reportStatus("大模型未开启，已使用本地整理")
            return try await local.structure(text, preferences: preferences)
        }
        guard apiStyle == .codexCLI || !apiKey.isEmpty else {
            await reportStatus("未找到 API Key，已使用本地整理")
            return try await local.structure(text, preferences: preferences)
        }
        let model = configurationResolver.resolvedModel(preferences: preferences, scope: scope)
        let apiURL = configurationResolver.resolvedAPIURL(preferences: preferences, scope: scope)
        guard isModelReady(model, apiStyle: apiStyle, apiURL: apiURL, preferences: preferences, scope: scope) else {
            await reportStatus("第三方兼容接口需要填写模型名称，已使用本地整理")
            return try await local.structure(text, preferences: preferences)
        }
        do {
            await reportStatus("正在请求大模型：\(apiStyle.displayName) / \(apiURL.host ?? apiURL.absoluteString) / \(model)")
            let promptStyle: NoteStructuringPromptStyle = preferences.preserveOriginalWhenStructuringEnabled == true ? .preserveOriginalText : .polishedNotes
            return try await provider.structureNotes(
                text: text,
                apiKey: apiKey,
                model: model,
                apiURL: apiURL,
                apiStyle: apiStyle,
                promptStyle: promptStyle,
                instructions: instructionsWithPhraseGlossary(preferences.resolvedStructuringPrompt, preferences: preferences)
            )
        } catch {
            await reportStatus("大模型请求失败：\(error.localizedDescription)")
            return try await local.structure(text, preferences: preferences)
        }
    }

    private func instructionsWithPhraseGlossary(_ base: String, preferences: Preferences) -> String {
        guard let glossary = phraseCorrection.promptGlossary(from: preferences) else {
            return base
        }
        return base + glossary
    }

    private func isModelReady(_ model: String, apiStyle: ModelAPIStyle, apiURL: URL, preferences: Preferences, scope: ModelConfigurationScope) -> Bool {
        if apiStyle == .anthropicMessages {
            return preferences.modelName(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard apiStyle == .openAICompatibleChat else {
            return true
        }
        let explicitModel = preferences.modelName(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitModel.isEmpty {
            return true
        }
        return apiURL.host?.localizedCaseInsensitiveContains("openai.com") == true && !model.isEmpty
    }
}

extension ModelAPIStyle: CaseIterable {
    public static var allCases: [ModelAPIStyle] {
        [.codexCLI, .openAIResponses, .openAICompatibleChat, .anthropicMessages]
    }

    var defaultAPIURL: URL {
        switch self {
        case .codexCLI, .openAIResponses:
            URL(string: "https://api.openai.com/v1/responses")!
        case .openAICompatibleChat:
            URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropicMessages:
            URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }

    var endpointPath: String {
        switch self {
        case .codexCLI:
            ""
        case .openAIResponses:
            "responses"
        case .openAICompatibleChat:
            "chat/completions"
        case .anthropicMessages:
            "messages"
        }
    }

    var displayName: String {
        switch self {
        case .codexCLI:
            "本地 Codex"
        case .openAIResponses:
            "OpenAI Responses"
        case .openAICompatibleChat:
            "OpenAI 兼容 Chat"
        case .anthropicMessages:
            "Claude 原生 Messages"
        }
    }
}

struct ResponsesAPITextResponse: Decodable {
    let status: String?
    let error: ResponseError?
    let incompleteDetails: IncompleteDetails?
    let output: [OutputItem]

    var outputText: String {
        output
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    func validatedOutputText() throws -> String {
        let text = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if status != nil || error != nil || incompleteDetails != nil {
                throw ModelProviderError.requestFailed
            }
            throw ModelProviderError.emptyResponse
        }
        if error != nil {
            throw ModelProviderError.requestFailed
        }
        return text
    }

    enum CodingKeys: String, CodingKey {
        case status
        case error
        case incompleteDetails = "incomplete_details"
        case output
    }

    struct OutputItem: Decodable {
        let content: [Content]
    }

    struct Content: Decodable {
        let text: String?
    }

    struct ResponseError: Decodable {}

    struct IncompleteDetails: Decodable {}
}

struct ChatCompletionsTextResponse: Decodable {
    let choices: [Choice]

    func validatedOutputText() throws -> String {
        let text = choices
            .compactMap(\.message.content?.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw ModelProviderError.emptyResponse
        }
        return text
    }

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: ChatMessageContent?
    }

    enum ChatMessageContent: Decodable {
        case string(String)
        case parts([ContentPart])

        var text: String? {
            switch self {
            case .string(let text):
                text
            case .parts(let parts):
                parts
                    .compactMap(\.text)
                    .joined(separator: "\n")
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .parts(try container.decode([ContentPart].self))
            }
        }
    }

    struct ContentPart: Decodable {
        let text: String?
    }
}

struct AnthropicMessagesTextResponse: Decodable {
    let content: [Content]

    func validatedOutputText() throws -> String {
        let text = content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw ModelProviderError.emptyResponse
        }
        return text
    }

    struct Content: Decodable {
        let text: String?
    }
}

public enum ModelProviderError: LocalizedError {
    case requestFailed
    case httpError(statusCode: Int, body: String)
    case responseParsingFailed(body: String, reason: String)
    case emptyResponse
    case codexUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed:
            "大模型请求失败，已回退到本地整理。"
        case .httpError(let statusCode, let body):
            body.isEmpty ? "大模型请求失败（HTTP \(statusCode)）。" : "大模型请求失败（HTTP \(statusCode)）：\(body)"
        case .responseParsingFailed(let body, let reason):
            body.isEmpty ? "大模型响应解析失败：\(reason)" : "大模型响应解析失败：\(reason)。响应：\(body)"
        case .emptyResponse:
            "大模型返回了空结果，已回退到本地整理。"
        case .codexUnavailable(let message):
            "Codex 本地调用失败：\(message)"
        }
    }
}
