# lesstype

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
![macOS](https://img.shields.io/badge/macOS-14%2B-black.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Tests](https://img.shields.io/badge/tests-swift%20test-brightgreen.svg)

[中文 README](./README.zh-CN.md)

> Talk instead of type. **lesstype** is a lightweight, native macOS voice input app: trigger dictation anywhere with a global hotkey, watch the recognition stream in a floating panel, and drop the final text straight into the app you're using.

It's built entirely with Swift, SwiftUI, AppKit, AVFoundation, and Apple's Speech framework — no Electron, no background daemon. Optional LLM post-processing can clean up everyday dictation or turn spoken notes into tidy numbered lists.

## Table of Contents

- [Why lesstype](#why-lesstype)
- [Screenshots](#screenshots)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Default Workflow](#default-workflow)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Model Configuration](#model-configuration)
- [Optional Codex/ChatGPT ASR](#optional-codexchatgpt-asr)
- [Development](#development)
- [Privacy and Security](#privacy-and-security)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## Why lesstype

- **Native and lightweight** — pure Swift/SwiftUI/AppKit, runs as a small menu bar app.
- **Works everywhere** — global hotkeys insert text into the currently focused app, not just a single editor.
- **Privacy-first** — audio stays local for live recognition; nothing leaves your machine unless you explicitly enable an LLM or cloud ASR provider.
- **Bring your own model** — OpenAI, OpenAI-compatible, Anthropic, or a local Codex CLI, with separate prompts per mode.
- **Tested core** — the state machine, hotkeys, model providers, and text processing are covered by XCTest.

## Screenshots

> Screenshots will be added after the first public release. Planned assets: settings window, floating preview panel, and menu bar status.

## Features

- **Global voice input**: start dictation from any macOS text field with customizable hotkeys.
- **Two input modes**:
  - *Ordinary* — clean up spoken text for direct insertion.
  - *Structured* — turn spoken notes into `1. 2. 3.` style numbered points.
- **Live preview**: optional floating panel with real-time recognition status and text.
- **One-key commit / discard**: finish and insert, or drop the current recording without inserting.
- **Text insertion**: types the result into the currently focused app.
- **Personal vocabulary**: high-frequency phrase correction for names, products, technical terms, and domain words.
- **LLM enhancement** (optional):
  - OpenAI Responses API
  - OpenAI-compatible Chat Completions APIs
  - Anthropic Messages API
  - Local Codex CLI provider
- **Custom prompts**: separate prompts for ordinary enhancement and structured notes.
- **Optional cloud transcription**: use an imported Codex/ChatGPT account for final ASR, with Apple Speech as fallback.
- **Settings and diagnostics**: hotkeys, recognition, model config, prompt editing, floating panel, launch at login, usage/status diagnostics, and recent input history.

## Requirements

- macOS 14 or later
- Xcode command line tools / Swift 6 toolchain
- Microphone permission
- Speech Recognition permission
- Accessibility permission — required for global hotkeys and text insertion

## Quick Start

### Download the app

Download the latest `lesstype-v*-macos.dmg` from [GitHub Releases](https://github.com/kevechang/lesstype/releases/latest), open it, then drag `lesstype.app` to `Applications`. A `.zip` package is also attached as a fallback.

The app is currently ad-hoc signed but not notarized. On first launch, macOS may ask you to confirm opening it from **System Settings → Privacy & Security**.

### Build from source

```bash
git clone https://github.com/kevechang/lesstype.git
cd lesstype

# build and test
swift build
swift test

# build and launch the .app bundle (output: dist/lesstype.app)
./script/build_and_run.sh

# package a release zip (output: dist/lesstype-v0.1.1-macos.zip)
./script/package_release.sh 0.1.1

# package a DMG installer (output: dist/lesstype-v0.1.1-macos.dmg)
./script/package_dmg.sh 0.1.1
```

On first launch, macOS may ask for Microphone, Speech Recognition, and Accessibility permissions. If hotkeys or text insertion don't work, grant access under:

```text
System Settings → Privacy & Security → Accessibility
System Settings → Privacy & Security → Microphone
System Settings → Privacy & Security → Speech Recognition
```

## Default Workflow

1. Press the ordinary-input hotkey to start dictation.
2. Speak naturally.
3. Press the commit hotkey to finish and insert.
4. Or press the discard hotkey to cancel the current session.

All hotkeys are configurable. Depending on your local preferences or migration state, defaults may differ — open **Settings → Shortcuts** to confirm them.

## Project Structure

```text
Package.swift
Sources/VoiceInputApp/
  App/        App entry, AppDelegate, floating panel presentation policy
  Models/     App state, preferences, shortcuts, settings sections
  Stores/     Preferences and secure persistence
  Services/   Speech recognition, audio capture, hotkeys, model APIs, text insertion
  Session/    Main voice-session state machine
  Support/    Small reusable utilities
  Views/      SwiftUI settings UI and AppKit floating panel
Tests/VoiceInputAppTests/   XCTest suites for the core logic
script/                     Build, run, and icon helper scripts
Resources/                  App icon and bundled assets
docs/                       Screenshots and public documentation
```

> Note: the Swift package and executable target are named `VoiceInputApp` for historical reasons; the shipped product is **lesstype**.

## Architecture

The app is organized around a small state machine:

```text
Hotkey → VoiceSessionCoordinator → Live Recognition → Optional Final ASR
       → Local or LLM Post-processing → Text Insertion → History/Status
```

Key components:

- `VoiceSessionCoordinator` — owns the recording / recognizing / processing / inserting state flow.
- `AppleLiveSpeechRecognitionService` — captures audio and provides live Apple Speech previews.
- `CodexASRFinalTranscriptionService` — optional final cloud transcription with fallback.
- `TextPostProcessor` — local punctuation, spacing, simplified Chinese conversion, and phrase correction.
- `CloudOrLocalNoteStructuringService` — structured notes with local fallback.
- `ModelBackedTextEnhancementService` — optional LLM cleanup for ordinary dictation.
- `HotkeyService` — global hotkey handling and active-session actions.
- `TextInsertionService` — inserts final text into the focused app.

## Model Configuration

Model configuration is managed in the app UI. Ordinary mode and structured mode are configured separately:

- API style
- API URL
- model name
- API key
- prompt text

API keys are stored outside normal `UserDefaults`. The app can also resolve keys from the environment or a local Codex configuration when using compatible workflows.

## Optional Codex/ChatGPT ASR

The app includes an optional final-transcription path that uses an imported Codex/ChatGPT credential and falls back to Apple Speech when it is unavailable, rate-limited, timed out, or fails.

This path depends on ChatGPT/Codex account behavior and is **not** an official public API. Treat it as experimental, optional, and **disabled by default** — it may change or stop working without notice.

## Development

```bash
swift test                  # run all tests
swift build                 # build only
./script/build_and_run.sh   # launch the local app bundle
```

When changing behavior, prefer adding or updating tests in `Tests/VoiceInputAppTests` for:

- state transitions
- hotkey behavior
- text post-processing
- model request/response parsing
- preferences migration
- ASR fallback behavior
- floating panel presentation policy

## Privacy and Security

- Audio is captured locally for live recognition.
- Apple Speech may use Apple's speech recognition services depending on macOS settings and availability.
- LLM enhancement sends recognized text to the configured model provider **only when enabled**.
- Optional cloud ASR sends recorded audio to the configured transcription endpoint **only when enabled**.
- API keys and imported ASR credentials should be stored securely and must never be committed to the repository.

Before publishing your own fork, scan the repository for local credentials, generated build artifacts, and personal files. See [SECURITY.md](./SECURITY.md).

## Roadmap

- Better onboarding for macOS permissions.
- Faster cancellation tests and improved async timeout handling.
- More robust local ASR provider abstraction.
- Optional Whisper / local model support.
- Better release packaging and signing flow.
- Expanded diagnostics for hotkey conflicts and insertion failures.

## Contributing

Issues and pull requests are welcome. Please keep the app lightweight, native, privacy-conscious, and testable. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the full flow.

1. Open an issue describing the problem or feature.
2. Add tests for behavior changes when practical.
3. Run `swift test` before submitting a pull request.
4. Avoid committing generated artifacts, credentials, or personal configuration files.

## License

Released under the MIT License. See [LICENSE](./LICENSE) for details.
