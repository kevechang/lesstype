# Changelog

## Unreleased

## v0.1.4

- Keep the Codex ASR m4a/AAC upload optimization while using a macOS 14-compatible AVFoundation export path.
- Remove the Swift concurrency warning around AVAssetExportSession in the legacy export callback.

## v0.1.3

- Convert Codex ASR uploads to temporary m4a/AAC before uploading when possible.
- Fall back to the original audio if m4a export fails or produces an empty file.
- Delete temporary upload audio after the ASR request finishes.
- Make Codex ASR timeout return immediately instead of waiting for slow cancellation cleanup.
- Added tests for prepared m4a upload cleanup and fast timeout fallback.

## v0.1.2

- Restored the public app/product name to typeart.
- Increased Codex ASR request and final-transcription timeout to 60 seconds.
- Improved Codex ASR progress status with wait time and audio file size.

## v0.1.1

- Added an unsigned DMG installer package.
- Updated README installation instructions to recommend the DMG download.
- Kept ZIP release packaging as a fallback.

- Initial open-source preparation.
