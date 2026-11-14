# Computa

Native Swift 6 / macOS 15 menu-bar prototype. Open `Computa.xcodeproj`, select the Computa scheme, and run. Signing team is configured as `V5W4LV96XX`. Regenerate the project with `xcodegen generate` after adding source files.

Use **Set up permissions** before the first capture. Hold Right Option to capture; release to finish. The menu also provides a capture button. Choose a built-in or wired input in macOS settings first: Bluetooth input is rejected before the engine is prepared.

Gemini is the default provider. Its API key is stored in macOS Keychain, outside the source and app bundle. The key from `~/Projects/twitter/.env` has been imported on this Mac. Allow Computa’s Keychain access prompt on first use.

To import or replace the key:

```sh
swift scripts/import-gemini-key.swift /path/to/.env
```

The personal build requests a single-use token directly from Google, then sends audio directly over the authenticated Live connection. A distributed build still needs an authenticated backend to issue tokens instead of provisioning a personal key on every Mac.

Endpoints:

- Token: `https://generativelanguage.googleapis.com/v1beta/auth_tokens`
- Live: `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained`
- Model: `gemini-3.5-transcribe-live`

Successful transcripts are inserted through Accessibility only if the original focused element is still focused; otherwise text is copied for manual paste. This fallback replaces the clipboard.

## Measuring

`-measureOnly YES` disables networking and insertion; `-selfTest N` runs N start/stop cycles through the hotkey path and quits. Cold = first cycle after launch.

```sh
open -W -n .build/xcode/Build/Products/Debug/Computa.app --args -measureOnly YES -selfTest 21
```

First run, 2026-11-14, SteelSeries Alias (USB, 48 kHz), 20 cold + 20 paused: call → first captured sample p50 75 ms / p90 89 ms cold, p50 74 ms / p90 97 ms paused. Raw data in `bench/capture-2026-11-14-steelseries-usb.jsonl`.

## Validation

```sh
swift test
xcodebuild -project Computa.xcodeproj -scheme Computa -configuration Debug CODE_SIGNING_ALLOWED=NO build
swift scripts/summarize.swift
```

Timing JSONL lives in `~/Library/Application Support/Computa/capture.jsonl`. It contains timing metadata, not audio or transcripts. Collect at least 20 independent cold launches and 20 paused trials. The summary reports request-to-start-return and request-to-first-callback percentiles. These are **not** physical key-event or acoustic-onset measurements.

## Implementation boundary

This is an initial foundation, not completion of all phases in PLAN.md. Implemented: native project, explicit permission setup, event tap, prepared/paused sink graph, C atomic single-producer/single-consumer queue, overflow accounting, signposts/JSONL, percentile summary, Gemini and Deepgram cloud adapters, and focus-checked insertion.

Still required before routine dictation use:

- Device-change and sleep/wake invalidation, automatic wired/built-in selection, per-chunk timestamps, and acoustic cross-correlation harness. Timing now starts at the key tap callback.
- Partial-result UI, cancellation, bounded session duration/backlog, and authenticated token refresh. Streaming now sends 16 kHz PCM16 from a pre-warmed Gemini session (refreshed every 4 min and after wake), and a failed stream is replayed whole through a fresh session. Neither the warm path nor the replay has been exercised with real speech yet.
- Other provider adapters, labeled corpus, truncated-onset evaluation, and measured provider selection. Gemini is the configured development provider, not a benchmark winner.
- Secure-input handling and verified clipboard-preserving paste across the application matrix.
- Cleanup/vocabulary, optional warm mic and provisional modifier experiments, suspicious-start detection, and offline child process.

No hardware latency, cloud latency, accuracy, RSS, or idle wakeup target has been claimed. Physical microphone tests have not been run. Gemini token issuance, authenticated Live setup, and synthetic-speech transcription through the native Swift adapter have been verified. This is a functional check, not a latency or accuracy benchmark. Permission denial and route changes require retrying setup/relaunching this prototype.

Deepgram wire format reference: https://developers.deepgram.com/reference/speech-to-text/listen-streaming

Gemini references: https://ai.google.dev/gemini-api/docs/live-api/live-transcribe and https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens
