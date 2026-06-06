import XCTest
@testable import VoiceInputApp

final class ModelProviderServiceTests: XCTestCase {
    func testCloudStructurerUsesLocalFallbackWhenDisabled() async throws {
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: FakeProvider(result: "1. 云端结果。"),
            configurationResolver: StaticConfigurationResolver(apiKey: "")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = false

        let result = try await service.structure("先本地识别 然后整理", preferences: preferences)

        XCTAssertEqual(result, "1. 先本地识别。\n2. 整理。")
    }

    func testCloudStructurerUsesProviderWhenEnabled() async throws {
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: FakeProvider(result: "1. 云端整理结果。"),
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = "test-key"

        let result = try await service.structure("原始文本", preferences: preferences)

        XCTAssertEqual(result, "1. 云端整理结果。")
    }

    func testCloudStructurerUsesLocalFallbackWhenApiKeyEmpty() async throws {
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: FakeProvider(result: "1. 云端整理结果。"),
            configurationResolver: StaticConfigurationResolver(apiKey: "")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = ""

        let result = try await service.structure("先本地识别 然后整理", preferences: preferences)

        XCTAssertEqual(result, "1. 先本地识别。\n2. 整理。")
    }

    func testCloudStructurerUsesLocalFallbackWhenApiKeyWhitespaceOnly() async throws {
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: FakeProvider(result: "1. 云端整理结果。"),
            configurationResolver: StaticConfigurationResolver(apiKey: "")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = " \n\t "

        let result = try await service.structure("先本地识别 然后整理", preferences: preferences)

        XCTAssertEqual(result, "1. 先本地识别。\n2. 整理。")
    }

    func testCloudStructurerUsesLocalFallbackWhenProviderThrows() async throws {
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: ThrowingProvider(),
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = "test-key"

        let result = try await service.structure("先本地识别 然后整理", preferences: preferences)

        XCTAssertEqual(result, "1. 先本地识别。\n2. 整理。")
    }

    func testCloudStructurerUsesResolvedCodexKeyWhenPreferencesKeyEmpty() async throws {
        let provider = RecordingProvider(result: "1. 云端整理结果。")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "codex-key", model: "gpt-5.5")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = ""

        let result = try await service.structure("原始文本", preferences: preferences)

        let apiKey = await provider.apiKey
        let model = await provider.model
        XCTAssertEqual(result, "1. 云端整理结果。")
        XCTAssertEqual(apiKey, "codex-key")
        XCTAssertEqual(model, "gpt-5.5")
    }

    func testCloudStructurerPassesPreserveOriginalPromptStyleWhenEnabled() async throws {
        let provider = RecordingProvider(result: "1. 原文第一段。\n2. 原文第二段。")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.preserveOriginalWhenStructuringEnabled = true

        _ = try await service.structure("原文第一段 原文第二段", preferences: preferences)

        let promptStyle = await provider.promptStyle
        XCTAssertEqual(promptStyle, .preserveOriginalText)
    }

    func testCodexResolverPrefersExplicitTrimmedApiKey() {
        let resolver = CodexOpenAIConfigurationResolver(environment: ["OPENAI_API_KEY": "env-key"])
        var preferences = Preferences.defaults
        preferences.apiKey = "  explicit-key \n"

        XCTAssertEqual(resolver.resolvedAPIKey(preferences: preferences), "explicit-key")
    }

    func testCodexResolverUsesModeSpecificApiKeysBeforeLegacyKey() {
        let resolver = CodexOpenAIConfigurationResolver(environment: ["OPENAI_API_KEY": "env-key"])
        var preferences = Preferences.defaults
        preferences.apiKey = "legacy-key"
        preferences.ordinaryAPIKey = "ordinary-key"
        preferences.structuredAPIKey = "structured-key"

        XCTAssertEqual(resolver.resolvedAPIKey(preferences: preferences, scope: .ordinary), "ordinary-key")
        XCTAssertEqual(resolver.resolvedAPIKey(preferences: preferences, scope: .structured), "structured-key")
    }

    func testCodexResolverUsesModeSpecificModelConfiguration() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .openAIResponses
        preferences.modelName = "legacy-model"
        preferences.apiURL = "https://api.openai.com/v1/responses"
        preferences.ordinaryModelAPIStyle = .openAICompatibleChat
        preferences.ordinaryModelName = "ordinary-model"
        preferences.ordinaryAPIURL = "https://ordinary.example/v1"
        preferences.structuredModelAPIStyle = .anthropicMessages
        preferences.structuredModelName = "structured-model"
        preferences.structuredAPIURL = "https://structured.example/v1"

        XCTAssertEqual(resolver.resolvedAPIStyle(preferences: preferences, scope: .ordinary), .openAICompatibleChat)
        XCTAssertEqual(resolver.resolvedModel(preferences: preferences, scope: .ordinary), "ordinary-model")
        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences, scope: .ordinary).absoluteString, "https://ordinary.example/v1/chat/completions")
        XCTAssertEqual(resolver.resolvedAPIStyle(preferences: preferences, scope: .structured), .anthropicMessages)
        XCTAssertEqual(resolver.resolvedModel(preferences: preferences, scope: .structured), "structured-model")
        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences, scope: .structured).absoluteString, "https://structured.example/v1/messages")
    }

    func testCodexResolverUsesCustomAPIURL() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.apiURL = "https://example.com/v1/responses"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://example.com/v1/responses")
    }

    func testCompatibleChatStyleAcceptsProviderBaseURL() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .openAICompatibleChat
        preferences.apiURL = "https://openrouter.ai/api/v1"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://openrouter.ai/api/v1/chat/completions")
    }

    func testCompatibleChatStyleAcceptsBareDeepSeekBaseURL() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .openAICompatibleChat
        preferences.apiURL = "https://api.deepseek.com"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://api.deepseek.com/chat/completions")
    }

    func testAnthropicMessagesStyleAcceptsProviderBaseURL() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .anthropicMessages
        preferences.apiURL = "https://api.anthropic.com/v1"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testCodexResolverUsesConfiguredAPIStyle() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .openAICompatibleChat

        XCTAssertEqual(resolver.resolvedAPIStyle(preferences: preferences), .openAICompatibleChat)
    }

    func testCompatibleChatStyleUsesChatEndpointWhenStoredURLIsResponsesDefault() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .openAICompatibleChat
        preferences.apiURL = "https://api.openai.com/v1/responses"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testOpenAIResponsesStyleUsesResponsesEndpointWhenStoredURLIsChatDefault() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .openAIResponses
        preferences.apiURL = "https://api.openai.com/v1/chat/completions"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://api.openai.com/v1/responses")
    }

    func testAnthropicMessagesStyleUsesMessagesEndpointWhenStoredURLIsBuiltInDefault() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelAPIStyle = .anthropicMessages
        preferences.apiURL = "https://api.openai.com/v1/chat/completions"

        XCTAssertEqual(resolver.resolvedAPIURL(preferences: preferences).absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testCodexResolverPrefersExplicitModelName() {
        let resolver = CodexOpenAIConfigurationResolver(environment: [:])
        var preferences = Preferences.defaults
        preferences.modelName = "  claude-3-5-sonnet-latest \n"

        XCTAssertEqual(resolver.resolvedModel(preferences: preferences), "claude-3-5-sonnet-latest")
    }

    func testOrdinaryEnhancementFallsBackWhenDisabled() async throws {
        let service = ModelBackedTextEnhancementService(
            provider: FakeProvider(result: "云端润色结果")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.ordinaryModelEnhancementEnabled = false

        let result = try await service.enhance("我想用 swift ui 做 app", preferences: preferences)

        XCTAssertEqual(result, "我想用 SwiftUI 做 app。")
    }

    func testOrdinaryEnhancementUsesProviderWhenEnabled() async throws {
        let service = ModelBackedTextEnhancementService(
            provider: FakeProvider(result: "云端润色结果"),
            configurationResolver: StaticConfigurationResolver(apiKey: "codex-login", apiStyle: .codexCLI)
        )
        var preferences = Preferences.defaults
        preferences.ordinaryModelEnhancementEnabled = true

        let result = try await service.enhance("原始文本", preferences: preferences)

        XCTAssertEqual(result, "云端润色结果")
    }

    func testOrdinaryEnhancementUsesOrdinaryModelConfiguration() async throws {
        let provider = RecordingProvider(result: "普通模型结果")
        let service = ModelBackedTextEnhancementService(
            provider: provider,
            configurationResolver: StaticConfigurationResolver(
                ordinaryAPIKey: "ordinary-key",
                structuredAPIKey: "structured-key",
                ordinaryModel: "ordinary-model",
                structuredModel: "structured-model",
                ordinaryAPIStyle: .openAICompatibleChat,
                structuredAPIStyle: .anthropicMessages
            )
        )
        var preferences = Preferences.defaults
        preferences.ordinaryModelEnhancementEnabled = true

        _ = try await service.enhance("原始文本", preferences: preferences)

        let apiKey = await provider.apiKey
        let model = await provider.model
        let apiStyle = await provider.apiStyle
        XCTAssertEqual(apiKey, "ordinary-key")
        XCTAssertEqual(model, "ordinary-model")
        XCTAssertEqual(apiStyle, .openAICompatibleChat)
    }

    func testOrdinaryEnhancementPassesCustomPromptToProvider() async throws {
        let provider = RecordingProvider(result: "云端润色结果")
        let service = ModelBackedTextEnhancementService(
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "codex-login", apiStyle: .codexCLI)
        )
        var preferences = Preferences.defaults
        preferences.ordinaryModelEnhancementEnabled = true
        preferences.ordinaryEnhancementPrompt = "自定义普通模式提示词"

        _ = try await service.enhance("原始文本", preferences: preferences)

        let instructions = await provider.instructions
        XCTAssertEqual(instructions, "自定义普通模式提示词")
    }

    func testOrdinaryEnhancementAppendsHighFrequencyPhrasesToPrompt() async throws {
        let provider = RecordingProvider(result: "云端润色结果")
        let service = ModelBackedTextEnhancementService(
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "codex-login", apiStyle: .codexCLI)
        )
        var preferences = Preferences.defaults
        preferences.ordinaryModelEnhancementEnabled = true
        preferences.ordinaryEnhancementPrompt = "自定义普通模式提示词"
        preferences.phraseCorrectionsText = "语音输入 App = 语音输入爱屁屁, 语音输入app"

        _ = try await service.enhance("原始文本", preferences: preferences)

        let instructions = await provider.instructions ?? ""
        XCTAssertTrue(instructions.contains("自定义普通模式提示词"))
        XCTAssertTrue(instructions.contains("高频词组"))
        XCTAssertTrue(instructions.contains("语音输入 App"))
        XCTAssertTrue(instructions.contains("语音输入爱屁屁"))
    }

    func testOrdinaryEnhancementAppendsStructuredHighFrequencyPhrasesToPrompt() async throws {
        let provider = RecordingProvider(result: "云端润色结果")
        let service = ModelBackedTextEnhancementService(
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "codex-login", apiStyle: .codexCLI)
        )
        var preferences = Preferences.defaults
        preferences.ordinaryModelEnhancementEnabled = true
        preferences.phraseCorrectionEntries = [
            PhraseCorrectionEntry(phrase: "Claude", variants: ["克劳德", "cloud"])
        ]

        _ = try await service.enhance("原始文本", preferences: preferences)

        let instructions = await provider.instructions ?? ""
        XCTAssertTrue(instructions.contains("Claude"))
        XCTAssertTrue(instructions.contains("克劳德"))
        XCTAssertTrue(instructions.contains("cloud"))
    }

    func testCloudStructurerPassesCustomPromptToProviderForSelectedMode() async throws {
        let provider = RecordingProvider(result: "1. 原文")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.preserveOriginalWhenStructuringEnabled = true
        preferences.preserveOriginalStructuringPrompt = "自定义仅分点提示词"

        _ = try await service.structure("原文", preferences: preferences)

        let instructions = await provider.instructions
        XCTAssertEqual(instructions, "自定义仅分点提示词")
    }

    func testCloudStructurerDefaultsToPreserveOriginalPromptStyle() async throws {
        let provider = RecordingProvider(result: "1. 原文")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true

        _ = try await service.structure("原文", preferences: preferences)

        let promptStyle = await provider.promptStyle
        let instructions = await provider.instructions ?? ""
        XCTAssertEqual(promptStyle, .preserveOriginalText)
        XCTAssertTrue(instructions.contains("不要改写"))
    }

    func testCloudStructurerUsesStructuredModelConfiguration() async throws {
        let provider = RecordingProvider(result: "1. 分点模型结果")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(
                ordinaryAPIKey: "ordinary-key",
                structuredAPIKey: "structured-key",
                ordinaryModel: "ordinary-model",
                structuredModel: "structured-model",
                ordinaryAPIStyle: .openAICompatibleChat,
                structuredAPIStyle: .anthropicMessages
            )
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.structuredModelName = "structured-model"

        _ = try await service.structure("原始文本", preferences: preferences)

        let apiKey = await provider.apiKey
        let model = await provider.model
        let apiStyle = await provider.apiStyle
        XCTAssertEqual(apiKey, "structured-key")
        XCTAssertEqual(model, "structured-model")
        XCTAssertEqual(apiStyle, .anthropicMessages)
    }

    func testCloudStructurerAppendsHighFrequencyPhrasesToPrompt() async throws {
        let provider = RecordingProvider(result: "1. 原文")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.preserveOriginalWhenStructuringEnabled = false
        preferences.polishedStructuringPrompt = "自定义分点提示词"
        preferences.phraseCorrectionsText = "OpenAI 兼容接口 = open ai 兼容接口"

        _ = try await service.structure("原文", preferences: preferences)

        let instructions = await provider.instructions ?? ""
        XCTAssertTrue(instructions.contains("自定义分点提示词"))
        XCTAssertTrue(instructions.contains("高频词组"))
        XCTAssertTrue(instructions.contains("OpenAI 兼容接口"))
        XCTAssertTrue(instructions.contains("open ai 兼容接口"))
    }

    func testDecodedChatCompletionReturnsMessageContent() throws {
        let response = try JSONDecoder().decode(
            ChatCompletionsTextResponse.self,
            from: #"{"choices":[{"message":{"content":"1. 整理结果。"}}]}"#.data(using: .utf8)!
        )

        XCTAssertEqual(try response.validatedOutputText(), "1. 整理结果。")
    }

    func testDecodedChatCompletionReturnsArrayContentText() throws {
        let response = try JSONDecoder().decode(
            ChatCompletionsTextResponse.self,
            from: #"{"choices":[{"message":{"content":[{"type":"text","text":"1. 整理结果。"}]}}]}"#.data(using: .utf8)!
        )

        XCTAssertEqual(try response.validatedOutputText(), "1. 整理结果。")
    }

    func testDecodedAnthropicMessageReturnsTextContent() throws {
        let response = try JSONDecoder().decode(
            AnthropicMessagesTextResponse.self,
            from: #"{"content":[{"type":"text","text":"1. Claude 整理结果。"}]}"#.data(using: .utf8)!
        )

        XCTAssertEqual(try response.validatedOutputText(), "1. Claude 整理结果。")
    }

    func testOpenAICompatibleChatRequestUsesStandardChatShape() async throws {
        let provider = OpenAIModelProvider(session: Self.mockedSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://third.example/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(request.httpBodyJSON)
            XCTAssertEqual(body["model"] as? String, "third-model")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
            return Self.response(
                body: #"{"choices":[{"message":{"content":"第三方返回"}}]}"#,
                url: request.url
            )
        })

        let result = try await provider.enhanceText(
            text: "原始文本",
            apiKey: "test-key",
            model: "third-model",
            apiURL: URL(string: "https://third.example/v1/chat/completions")!,
            apiStyle: .openAICompatibleChat
        )

        XCTAssertEqual(result, "第三方返回")
    }

    func testOpenAIProviderCachesRepeatedIdenticalRequests() async throws {
        let requestCount = RequestCounter()
        let provider = OpenAIModelProvider(session: Self.mockedSession { request in
            requestCount.increment()
            return Self.response(
                body: #"{"choices":[{"message":{"content":"缓存后的结果"}}]}"#,
                url: request.url
            )
        })

        let first = try await provider.enhanceText(
            text: "同一段原文",
            apiKey: "test-key",
            model: "third-model",
            apiURL: URL(string: "https://third.example/v1/chat/completions")!,
            apiStyle: .openAICompatibleChat,
            instructions: "同一个提示词"
        )
        let second = try await provider.enhanceText(
            text: "同一段原文",
            apiKey: "test-key",
            model: "third-model",
            apiURL: URL(string: "https://third.example/v1/chat/completions")!,
            apiStyle: .openAICompatibleChat,
            instructions: "同一个提示词"
        )

        XCTAssertEqual(first, "缓存后的结果")
        XCTAssertEqual(second, "缓存后的结果")
        XCTAssertEqual(requestCount.value, 1)
    }

    func testOpenAICompatibleChatStreamingRequestParsesDeltas() async throws {
        let provider = OpenAIModelProvider(session: Self.mockedSession { request in
            let body = try XCTUnwrap(request.httpBodyJSON)
            XCTAssertEqual(body["stream"] as? Bool, true)
            return Self.response(
                body: """
                data: {"choices":[{"delta":{"content":"流式"}}]}

                data: {"choices":[{"delta":{"content":"返回"}}]}

                data: [DONE]

                """,
                url: request.url
            )
        })

        let result = try await provider.streamText(
            text: "原始文本",
            apiKey: "test-key",
            model: "third-model",
            apiURL: URL(string: "https://third.example/v1/chat/completions")!,
            apiStyle: .openAICompatibleChat,
            instructions: "整理"
        )

        XCTAssertEqual(result, "流式返回")
    }

    func testOrdinaryEnhancementPromptCorrectsSimilarSoundWordsAndUsesSpacesForPauses() async throws {
        let provider = OpenAIModelProvider(session: Self.mockedSession { request in
            let body = try XCTUnwrap(request.httpBodyJSON)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let systemPrompt = try XCTUnwrap(messages.first?["content"])
            XCTAssertTrue(systemPrompt.contains("读音相近"))
            XCTAssertTrue(systemPrompt.contains("误识别"))
            XCTAssertTrue(systemPrompt.contains("标点位置用空格"))
            XCTAssertTrue(systemPrompt.contains("帮助断句"))
            XCTAssertFalse(systemPrompt.contains("中文标点"))
            return Self.response(
                body: #"{"choices":[{"message":{"content":"纠正后的文本 分成短句"}}]}"#,
                url: request.url
            )
        })

        let result = try await provider.enhanceText(
            text: "语音转写原文",
            apiKey: "test-key",
            model: "third-model",
            apiURL: URL(string: "https://third.example/v1/chat/completions")!,
            apiStyle: .openAICompatibleChat
        )

        XCTAssertEqual(result, "纠正后的文本 分成短句")
    }

    func testCodexOrdinaryEnhancementPromptCorrectsSimilarSoundWordsAndUsesSpacesForPauses() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceinput-codex-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let executableURL = temporaryDirectory.appendingPathComponent("codex")
        let capturedPromptURL = temporaryDirectory.appendingPathComponent("prompt.txt")
        let script = """
        #!/bin/bash
        output=""
        last=""
        while [[ "$#" -gt 0 ]]; do
          if [[ "$1" == "--output-last-message" ]]; then
            shift
            output="$1"
          fi
          last="$1"
          shift
        done
        printf "%s" "$last" > "\(capturedPromptURL.path)"
        printf "%s" "codex result" > "$output"
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let provider = CodexCLIModelProvider(executableCandidates: [executableURL])
        let result = try await provider.enhanceText(
            text: "语音转写原文",
            apiKey: "",
            model: "",
            apiURL: URL(string: "https://api.openai.com/v1/responses")!,
            apiStyle: .codexCLI
        )
        let capturedPrompt = try String(contentsOf: capturedPromptURL, encoding: .utf8)

        XCTAssertEqual(result, "codex result")
        XCTAssertTrue(capturedPrompt.contains("读音相近"))
        XCTAssertTrue(capturedPrompt.contains("误识别"))
        XCTAssertTrue(capturedPrompt.contains("标点位置用空格"))
        XCTAssertTrue(capturedPrompt.contains("帮助断句"))
        XCTAssertFalse(capturedPrompt.contains("中文标点"))
    }

    func testOpenAICompatibleChatPreserveOriginalPromptDoesNotAskModelToRewrite() async throws {
        let provider = OpenAIModelProvider(session: Self.mockedSession { request in
            let body = try XCTUnwrap(request.httpBodyJSON)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let systemPrompt = try XCTUnwrap(messages.first?["content"])
            XCTAssertTrue(systemPrompt.contains("不要改写"))
            XCTAssertTrue(systemPrompt.contains("只添加编号"))
            XCTAssertFalse(systemPrompt.contains("去掉口水词"))
            return Self.response(
                body: #"{"choices":[{"message":{"content":"1. 原文内容"}}]}"#,
                url: request.url
            )
        })

        let result = try await provider.structureNotes(
            text: "原文内容",
            apiKey: "test-key",
            model: "third-model",
            apiURL: URL(string: "https://third.example/v1/chat/completions")!,
            apiStyle: .openAICompatibleChat,
            promptStyle: .preserveOriginalText
        )

        XCTAssertEqual(result, "1. 原文内容")
    }

    func testAnthropicMessagesRequestUsesNativeHeadersAndBody() async throws {
        let provider = OpenAIModelProvider(session: Self.mockedSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(request.httpBodyJSON)
            XCTAssertEqual(body["model"] as? String, "claude-test")
            XCTAssertEqual(body["max_tokens"] as? Int, 1024)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.first?["role"], "user")
            return Self.response(
                body: #"{"content":[{"type":"text","text":"Claude 返回"}]}"#,
                url: request.url
            )
        })

        let result = try await provider.structureNotes(
            text: "原始文本",
            apiKey: "anthropic-key",
            model: "claude-test",
            apiURL: URL(string: "https://api.anthropic.com/v1/messages")!,
            apiStyle: .anthropicMessages
        )

        XCTAssertEqual(result, "Claude 返回")
    }

    func testModelProviderErrorIncludesHTTPStatusAndBody() {
        let error = ModelProviderError.httpError(statusCode: 401, body: #"{"error":{"message":"invalid api key"}}"#)

        XCTAssertTrue(error.localizedDescription.contains("401"))
        XCTAssertTrue(error.localizedDescription.contains("invalid api key"))
    }

    func testCloudStructurerUsesResolvedApiKeyBeforeCallingProvider() async throws {
        let provider = RecordingProvider(result: "1. 云端整理结果。")
        let service = CloudOrLocalNoteStructuringService(
            local: LocalNoteStructuringService(),
            provider: provider,
            configurationResolver: StaticConfigurationResolver(apiKey: "test-key")
        )
        var preferences = Preferences.defaults
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = "  test-key \n"

        _ = try await service.structure("原始文本", preferences: preferences)

        let apiKey = await provider.apiKey
        XCTAssertEqual(apiKey, "test-key")
    }

    func testDecodedOpenAIResponseRejectsEmptyOutput() throws {
        let response = try JSONDecoder().decode(
            ResponsesAPITextResponse.self,
            from: #"{"output":[{"content":[{"text":"  \n "}]}]}"#.data(using: .utf8)!
        )

        XCTAssertThrowsError(try response.validatedOutputText())
    }

    func testDecodedOpenAIResponseRejectsIncompleteWithoutOutput() throws {
        let response = try JSONDecoder().decode(
            ResponsesAPITextResponse.self,
            from: #"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.data(using: .utf8)!
        )

        XCTAssertThrowsError(try response.validatedOutputText())
    }

    func testDecodedOpenAIResponseRejectsErrorWithoutOutput() throws {
        let response = try JSONDecoder().decode(
            ResponsesAPITextResponse.self,
            from: #"{"status":"failed","error":{"message":"bad request"},"output":[]}"#.data(using: .utf8)!
        )

        XCTAssertThrowsError(try response.validatedOutputText())
    }

    private static func mockedSession(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(body: String, url: URL?) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            body.data(using: .utf8)!
        )
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ModelProviderError.requestFailed)
            return
        }
        do {
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

private extension URLRequest {
    var httpBodyJSON: [String: Any]? {
        let body = httpBody ?? httpBodyStream?.readAllData()
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object
    }
}

private extension InputStream {
    func readAllData() -> Data {
        open()
        defer { close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while hasBytesAvailable {
            let count = read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}

private struct FakeProvider: ModelProviding {
    let result: String
    func structureNotes(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, promptStyle: NoteStructuringPromptStyle, instructions: String) async throws -> String {
        result
    }

    func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        result
    }
}

private struct ThrowingProvider: ModelProviding {
    func structureNotes(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, promptStyle: NoteStructuringPromptStyle, instructions: String) async throws -> String {
        throw ModelProviderError.requestFailed
    }

    func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        throw ModelProviderError.requestFailed
    }
}

private actor RecordingProvider: ModelProviding {
    let result: String
    private(set) var apiKey: String?
    private(set) var model: String?
    private(set) var apiURL: URL?
    private(set) var apiStyle: ModelAPIStyle?
    private(set) var promptStyle: NoteStructuringPromptStyle?
    private(set) var instructions: String?

    init(result: String) {
        self.result = result
    }

    func structureNotes(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, promptStyle: NoteStructuringPromptStyle, instructions: String) async throws -> String {
        self.apiKey = apiKey
        self.model = model
        self.apiURL = apiURL
        self.apiStyle = apiStyle
        self.promptStyle = promptStyle
        self.instructions = instructions
        return result
    }

    func enhanceText(text: String, apiKey: String, model: String, apiURL: URL, apiStyle: ModelAPIStyle, instructions: String) async throws -> String {
        self.apiKey = apiKey
        self.model = model
        self.apiURL = apiURL
        self.apiStyle = apiStyle
        self.instructions = instructions
        return result
    }
}

private struct StaticConfigurationResolver: OpenAIConfigurationResolving {
    var apiKey = ""
    var model = "gpt-4.1-mini"
    var apiStyle = ModelAPIStyle.openAIResponses
    var ordinaryAPIKey: String?
    var structuredAPIKey: String?
    var ordinaryModel: String?
    var structuredModel: String?
    var ordinaryAPIStyle: ModelAPIStyle?
    var structuredAPIStyle: ModelAPIStyle?

    func resolvedAPIKey(preferences: Preferences) -> String {
        apiKey
    }

    func resolvedAPIKey(preferences: Preferences, scope: ModelConfigurationScope) -> String {
        switch scope {
        case .ordinary:
            ordinaryAPIKey ?? apiKey
        case .structured:
            structuredAPIKey ?? apiKey
        }
    }

    func resolvedModel(preferences: Preferences) -> String {
        model
    }

    func resolvedModel(preferences: Preferences, scope: ModelConfigurationScope) -> String {
        switch scope {
        case .ordinary:
            ordinaryModel ?? model
        case .structured:
            structuredModel ?? model
        }
    }

    func resolvedAPIURL(preferences: Preferences) -> URL {
        URL(string: preferences.apiURL ?? "https://api.openai.com/v1/responses")!
    }

    func resolvedAPIURL(preferences: Preferences, scope: ModelConfigurationScope) -> URL {
        resolvedAPIURL(preferences: preferences)
    }

    func resolvedAPIStyle(preferences: Preferences) -> ModelAPIStyle {
        apiStyle
    }

    func resolvedAPIStyle(preferences: Preferences, scope: ModelConfigurationScope) -> ModelAPIStyle {
        switch scope {
        case .ordinary:
            ordinaryAPIStyle ?? apiStyle
        case .structured:
            structuredAPIStyle ?? apiStyle
        }
    }
}
