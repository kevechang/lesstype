# lesstype

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
![macOS](https://img.shields.io/badge/macOS-14%2B-black.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Tests](https://img.shields.io/badge/tests-swift%20test-brightgreen.svg)

[English README](./README.md)

> 用说的，少打字。**lesstype** 是一个轻量级原生 macOS 语音输入 App：在任意场景用全局快捷键开始语音输入，在浮窗里看实时识别结果，然后把最终文本直接插入到你正在用的 App 里。

项目完全使用 Swift、SwiftUI、AppKit、AVFoundation 和 Apple Speech framework 构建——没有 Electron，也没有后台守护进程。可选的大模型后处理能把普通口语整理成规整文本，或把分点笔记整理成编号列表。

## 目录

- [为什么选 lesstype](#为什么选-lesstype)
- [截图](#截图)
- [功能特性](#功能特性)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [默认使用流程](#默认使用流程)
- [项目结构](#项目结构)
- [架构说明](#架构说明)
- [模型配置](#模型配置)
- [可选 Codex/ChatGPT ASR](#可选-codexchatgpt-asr)
- [开发命令](#开发命令)
- [隐私与安全](#隐私与安全)
- [路线规划](#路线规划)
- [贡献](#贡献)
- [许可证](#许可证)

## 为什么选 lesstype

- **原生且轻量**——纯 Swift/SwiftUI/AppKit，以小巧的菜单栏 App 形式运行。
- **随处可用**——全局快捷键把文本插入到当前聚焦的 App，而不只是某一个编辑器。
- **隐私优先**——实时识别的音频留在本地；除非你主动开启大模型或云端 ASR，否则数据不会离开你的电脑。
- **自带模型**——支持 OpenAI、OpenAI 兼容接口、Anthropic 或本地 Codex CLI，且两种模式可分别配置提示词。
- **核心有测试**——状态机、快捷键、模型 provider、文本处理均有 XCTest 覆盖。

## 截图

> 截图会在第一次公开 release 后补充。计划包含：设置窗口、浮窗实时预览、菜单栏状态。

## 功能特性

- **全局语音输入**：在任意 macOS 文本输入框中用快捷键开始听写。
- **两种输入模式**：
  - *普通模式*——整理成适合直接插入的文本。
  - *分点模式*——整理成 `1. 2. 3.` 形式的编号列表。
- **实时预览**：可选浮窗展示当前识别状态和实时文本。
- **一键完成 / 放弃**：结束后自动插入，或放弃本次录音且不插入。
- **文本插入**：把最终文本输入到当前聚焦的 App。
- **个人高频词**：支持高频词组和易错词修正，适合人名、产品名、技术词和专业术语。
- **大模型增强**（可选）：
  - OpenAI Responses API
  - OpenAI 兼容 Chat Completions API
  - Anthropic Messages API
  - 本地 Codex CLI provider
- **自定义提示词**：普通模式和分点模式可以分别配置提示词。
- **可选云端转写**：可导入 Codex/ChatGPT 账号用于最终 ASR，失败时自动回退到 Apple Speech 结果。
- **设置和诊断**：快捷键、识别与 ASR、模型配置、提示词、浮窗、开机启动、状态诊断、最近输入历史等。

## 环境要求

- macOS 14 或更高版本
- Xcode Command Line Tools / Swift 6 工具链
- 麦克风权限
- 语音识别权限
- 辅助功能权限——用于全局快捷键和文本插入

## 快速开始

目前还没有预构建安装包，请先从源码构建运行。

```bash
git clone https://github.com/kevechang/lesstype.git
cd lesstype

# 构建并运行测试
swift build
swift test

# 构建并启动 .app（产物：dist/lesstype.app）
./script/build_and_run.sh

# 构建并验证 App 能否成功启动，随后退出
./script/build_and_run.sh --verify
```

首次启动时，macOS 可能会请求麦克风、语音识别和辅助功能权限。如果快捷键或文本插入不可用，请在以下位置授权：

```text
系统设置 → 隐私与安全性 → 辅助功能
系统设置 → 隐私与安全性 → 麦克风
系统设置 → 隐私与安全性 → 语音识别
```

## 默认使用流程

1. 按普通输入快捷键开始听写。
2. 自然说话。
3. 按完成快捷键结束并插入。
4. 或按放弃快捷键取消本次输入。

所有快捷键都可以自定义。由于本地偏好设置或迁移状态不同，默认快捷键可能不同——请打开 **设置 → 快捷键** 查看当前配置。

## 项目结构

```text
Package.swift
Sources/VoiceInputApp/
  App/        App 入口、AppDelegate、浮窗显示策略
  Models/     App 状态、偏好设置、快捷键、设置分区
  Stores/     偏好设置和安全持久化
  Services/   语音识别、音频采集、快捷键、模型 API、文本插入
  Session/    语音输入主状态机
  Support/    小型通用辅助工具
  Views/      SwiftUI 设置界面和 AppKit 浮窗
Tests/VoiceInputAppTests/   核心逻辑的 XCTest 测试
script/                     构建、运行、图标处理脚本
Resources/                  App 图标和资源文件
docs/                       截图和公开文档
```

> 说明：由于历史原因，Swift package 和可执行 target 名为 `VoiceInputApp`；实际发布的产品名是 **lesstype**。

## 架构说明

App 以一个小型状态机为中心：

```text
快捷键 → VoiceSessionCoordinator → 实时识别 → 可选最终 ASR
      → 本地或大模型后处理 → 文本插入 → 历史记录 / 状态展示
```

关键组件：

- `VoiceSessionCoordinator`——管理录音、识别、处理、插入的完整状态流。
- `AppleLiveSpeechRecognitionService`——采集音频并提供 Apple Speech 实时预览。
- `CodexASRFinalTranscriptionService`——可选最终云端转写，并带自动回退。
- `TextPostProcessor`——本地标点、空格、简体中文转换和高频词修正。
- `CloudOrLocalNoteStructuringService`——分点整理，支持本地 fallback。
- `ModelBackedTextEnhancementService`——普通模式的大模型文本修正。
- `HotkeyService`——全局快捷键和录音中快捷操作。
- `TextInsertionService`——把最终文本插入到当前聚焦的 App。

## 模型配置

模型配置在 App 设置界面中管理。普通模式和分点模式可以分别配置：

- API 类型
- API URL
- 模型名称
- API Key
- 提示词

API Key 不会直接保存在普通 `UserDefaults` 中。部分工作流也可以从环境变量或本地 Codex 配置中解析密钥。

## 可选 Codex/ChatGPT ASR

项目包含一个可选的最终转写路径：导入 Codex/ChatGPT 凭证后，结束录音时可以使用该账号进行云端 ASR；如果不可用、超时、限流或失败，会自动回退到 Apple Speech 的识别结果。

这个功能依赖 ChatGPT/Codex 账号行为，**并不是**官方公开 API。请把它视为实验性、可选、且**默认关闭**的功能——它可能随时变化或失效。

## 开发命令

```bash
swift test                  # 运行全部测试
swift build                 # 只构建
./script/build_and_run.sh   # 启动本地 App 包
```

修改行为时，建议同步补充或更新 `Tests/VoiceInputAppTests` 中的测试，尤其是：

- 状态流转
- 快捷键行为
- 文本后处理
- 模型请求和响应解析
- 偏好设置迁移
- ASR 回退逻辑
- 浮窗显示策略

## 隐私与安全

- 实时识别会在本地采集音频。
- Apple Speech 是否使用 Apple 的语音识别服务，取决于 macOS 设置和系统可用性。
- 只有在**开启**大模型增强时，识别后的文本才会发送给你配置的模型 provider。
- 只有在**开启**云端 ASR 时，录音文件才会发送给配置的转写端点。
- API Key 和导入的 ASR 凭证应安全保存，绝不能提交到 Git 仓库。

正式公开仓库前，请检查是否包含本地凭证、构建产物、个人配置或临时文件。详见 [SECURITY.md](./SECURITY.md)。

## 路线规划

- 更清晰的 macOS 权限引导。
- 优化异步取消测试和 timeout 设计。
- 更稳定的本地 ASR provider 抽象。
- 可选 Whisper / 本地模型支持。
- 更完善的发布、签名和打包流程。
- 增强快捷键冲突、插入失败等诊断能力。

## 贡献

欢迎提交 issue 和 pull request。请保持这个 App 的核心方向：轻量、原生、重视隐私、易测试。完整流程见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

1. 先开 issue 描述问题或功能需求。
2. 涉及行为变化时尽量补充测试。
3. 提交 PR 前运行 `swift test`。
4. 不要提交构建产物、密钥或个人配置文件。

## 许可证

本项目基于 MIT License 开源。详情见 [LICENSE](./LICENSE)。
