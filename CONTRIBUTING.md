# Contributing

Thanks for your interest in contributing to lesstype.

## Development

```bash
swift build
swift test
./script/build_and_run.sh
```

Please add or update tests when changing behavior in:

- voice session state transitions
- hotkeys
- text post-processing
- model provider request/response parsing
- preferences migration
- ASR fallback behavior
- floating panel presentation

## Pull requests

Before opening a pull request:

1. Run `swift test` locally.
2. Keep changes focused and easy to review.
3. Do not commit build artifacts, local configuration, API keys, credentials, or personal notes.
4. Explain user-visible behavior changes in the PR description.
