# Dictation App Comparison

Investigation date: 2026-11-10

This compares the approach, speed and memory of open-source Mac dictation apps against the HeyClicky and Spokenly reverse-engineering notes in [`../heyclicky`](../heyclicky) and [`../spokenly`](../spokenly/findings.md).

## Evidence strength (read first)

- **Nothing here was measured.** No app was installed or run for this comparison.
- **"From code"** means read in the source at the commit listed below.
- **"Estimate"** means inferred from model file sizes or architecture. Treat these as rough ranges.
- **Cloud-versus-local latency figures** are general knowledge, not tests.

## User context

- The Mac has 16 GB of memory, which Chrome tabs usually fill. Giving up about 500 MB to a resident local model is not acceptable, so **cloud transcription is the preferred direction**.
- **Talkify is ruled out.** Apple's built-in speech engine is not accurate enough.

## Sources

The clones were shallow and were deleted with the session scratchpad.

| Repo | Commit | Date | Note |
|---|---|---|---|
| saurabhav88/EnviousWispr | `b6e5518` | 2026-11-09 | |
| altic-dev/FluidVoice | `695eb87` | 2026-11-06 | |
| cjpais/Handy | `73cc857` | 2026-11-06 | |
| tornikegomareli/Talkify | `6c2f7c6` | 2026-10-17 | |
| afar1/fieldtheory | `1e1d1af` | 2026-07-03 | Mac app, which contains Hot Mic |
| afar1/fieldtheory-cli | `542c116` | 2026-09-05 | X-bookmarks CLI; not voice-related |

Also read: <https://www.fieldtheory.dev/hot-mic.html> (fetched 2026-11-10) and EnviousWispr PR #86 (merged 2026-03-31).

## 1. The four open-source local apps

### Talkify (ruled out for accuracy)

- Uses Apple's `SpeechAnalyzer`/`SpeechTranscriber`, with no model of its own. macOS downloads and hosts the model; the code uses `AssetInventory` to reserve locales.
- Uses `FoundationModels` for prompt shaping and makes no network requests.
- About 160 Swift files and almost no dependencies.
- Requires macOS 26 and Apple Silicon.
- Memory: lowest of the four, because the model lives in a macOS process (estimate).

### Handy (cross-platform; Rust + Tauri)

- Every model runs through transcribe-cpp (GGUF/ggml) in a separate child process (from code: `src-tauri/src/engine_supervisor/mod.rs`). A GPU crash or hang kills only that process, and it retries on the CPU.
- Unloading the model ends that process, so all model memory goes back to the OS. The unload timeout options are Never, Immediately, 2/5/10/15 min and 1 hour (`settings.rs`).
- Uses the Silero speech detector.

Model file sizes (`src-tauri/src/managers/model.rs`):

| Model | Size |
|---|---|
| Moonshine V2 Tiny | 31 MB |
| Moonshine Base | 55 MB |
| Moonshine V2 Small | 99 MB |
| Canary 180M Flash | 146 MB |
| GigaAM v3 | 151 MB |
| SenseVoice | 152 MB |
| Moonshine V2 Medium | 192 MB |
| Parakeet V2 | 451 MB |
| Parakeet V3 | 456 MB |
| Whisper Small | 465 MB |
| Whisper Medium q4_1 | 469 MB |
| Canary 1B v2 | 691 MB |
| Breeze ASR | 1030 MB |
| Whisper Large v3 q5_0 | 1031 MB |
| Whisper Large v3 Turbo | 1549 MB |
| Cohere | 1708 MB |

### FluidVoice (native Swift, Mac only)

- Runs Parakeet through FluidAudio (CoreML on the Neural Engine) and shows text while you speak.
- Also supports Whisper (transcribe-cpp-swift), Apple Speech and Cohere.
- Optional cleanup comes from "Fluid Intelligence", a closed-source local AI runtime.
- Its experimental "Free memory when idle" option only covers that cleanup model.

### EnviousWispr (native Swift; the largest codebase, at about 2,247 Swift files)

- Parakeet through FluidAudio on the Neural Engine. Whisper runs through transcribe.cpp, and the argmax-oss-swift package is also a dependency.
- Cleanup models: EG-1 (2.9 GB resident by the code's own comment; warns on 8 GB Macs), S1-mini (484 MB), Apple Intelligence, Ollama, or bring-your-own cloud key (OpenAI, Gemini, Claude).
- Extras: a dictionary/word-check model (kev-wc, about 486 MB), meeting transcription, an Android app, and PostHog + Sentry. Some extra models unload after 10 minutes idle.
- Its README claims 400–800 ms to transcribe, plus 200–500 ms for AI cleanup.
- A code comment mentions a Mac holding about 500 MB with nobody dictating.

### Speed and memory summary (estimates)

**Fastest local:** FluidVoice (Parakeet on the Neural Engine, with the least extra weight).

| App | Memory with the speech model loaded |
|---|---|
| Talkify | Tens of MB in its own process (macOS hosts the model) |
| Handy | Moonshine about 100–150 MB; Parakeet/Whisper Small about 500–700 MB; Whisper Large Turbo about 1.6–2 GB; zero when unloaded |
| FluidVoice | Parakeet about 500–700 MB; Fluid Intelligence size unknown |
| EnviousWispr | Parakeet about 500–700 MB; Whisper Turbo about 1–1.2 GB; with EG-1 about 3.5 GB or more |

Rule of thumb: loaded memory is roughly the model file size plus audio buffers and working space. macOS can page model weights out under pressure, which slows the next dictation.

## 2. HeyClicky (cloud)

Summary of [`../heyclicky/README.txt`](../heyclicky/README.txt).

- Streams PCM16 audio over a WebSocket directly to Google, model `models/gemini-3.5-transcribe-live`. This was verified from the app's network traffic.
- A token comes from `api.heyclicky.com` `/v2/dictation/gemini-token`.
- Pre-warms the connection (`WarmStreamingConnection`).
- Cleanup runs on the server (`/v2/dictation/cleanup`). When streaming fails, it falls back to `/v2/dictation/transcribe`. When cleanup fails, it inserts the raw text.
- Sends context: app name, text before and after the cursor, selected text, custom vocabulary.
- Dictation is one subsystem of a large AI-assistant app: a 368 MB package, including a 136 MB helper, plus Sentry and PostHog.
- Uses no local model memory for transcription, but the app as a whole is heavy.
- Latency was never measured, and microphone pre-roll is not proven.

## 3. Spokenly 2.35.6

Summary of [`../spokenly/findings.md`](../spokenly/findings.md).

- Starts a fresh `AVAudioRecorder` on every keypress, with no pre-roll buffer.
- Checks the mic level every 30 ms and plays the start sound once the mic is live, so the recording starts before the sound.
- After recording, `StartCueSilencer` can zero out about 370 ms where the start sound was found, erasing any speech in that stretch. Turning off the start sound skips this step.
- Streams by polling the recording file every 100 ms and sending chunks of about 450 ms. It queues audio until the connection is ready, then falls back to transcribing the file.
- Bundles FluidAudio, so its local mode probably uses memory like FluidVoice (unverified).

## 4. EnviousWispr PR #86: pre-roll and warm mic

- Keeps the audio engine running between recordings and holds a 500 ms ring buffer at 16 kHz in `PreRollForwarder`. On keypress, the buffered audio is placed in front of the recording in strict order.
- Warm-mic timeout: 30 s in the PR. The app now offers `WarmEnginePolicy`: off, 10 s, 30 s, 60 s or always.
- Tap buffer size went from 4096 to 2048. Also adds crash hardening for codec and route changes.
- Still in the current code (`Sources/EnviousWisprAudio/PreRollForwarder.swift`).
- Limits: a cold start still has about a 55 ms gap (down from about 115 ms). The mic stays on, which likely keeps the orange indicator visible and may push Bluetooth headsets into call mode.
- Testing was only 10/10 rapid push-to-talk recordings. The cold-start, idle and Bluetooth items in the PR's test plan are unchecked.
- **This is the best first-word handling of all the apps reviewed.**

## 5. Field Theory Hot Mic

- `fieldtheory-cli` syncs X bookmarks and has nothing to do with voice. Hot Mic is in the `afar1/fieldtheory` Mac app (Electron + a native Swift helper).
- Always-on mic with no push-to-talk key, controlled by spoken phrases: submit ("go ahead"), paste, cancel, plus commands for apps, windows and media.
- Each chunk is transcribed locally after it is cut. This is not true streaming.
- Waits for five words before showing text. An optional background voice filter is off by default, with strictness 0–100 (default 4).

Chunking (from code: `electron/native/Sources/FieldTheoryHelper/main.swift`):

| Setting | Value |
|---|---|
| Silence to cut a chunk | 200 ms (dictation) or 300 ms (command); the Parakeet override is 0 |
| Forced maximum chunk length | 15 s (dictation) or 300 ms (command) |
| Chunk dropped when | Less than 170 ms of speech, or under 14% speech |
| Backpressure | Switches to longer chunks; drops the oldest chunk when the queue is full |

Engines:

- **Parakeet TDT 0.6B v2/v3** through onnx-asr in a Python process, with the CPU forced (CoreML errored).
- **whisper.cpp.**
- **mlx-whisper Large v3 Turbo.**
- **No cloud transcription.** Auto-improve can use local, Codex or Claude, but not in Hot Mic mode.

Memory: `load_model` has no quantization, so it is likely full-precision Parakeet at about 2–3 GB, plus Python and Electron. Probably the heaviest setup reviewed (estimate).

Self-described as very experimental. One-word commands and nearby voices cause false triggers. Requires macOS 14+ on Apple Silicon.

## 6. Cloud versus local latency

General knowledge, not measured.

| Approach | Key release to text |
|---|---|
| Cloud, streaming while you talk | About 150–500 ms |
| Cloud, upload after release | About 0.5–2 s |
| Local Parakeet on the Neural Engine | About 100–400 ms for short dictations |
| Local, model loaded per use | Adds about 0.5–2 s |

- Streaming cloud roughly matches local. Local is more consistent for short phrases, and cloud can come out ahead on long dictations.
- Cloud costs: connection setup (100–300 ms unless pre-warmed), network quality and VPNs, and server distance (100–200 ms per round trip to another continent).
- AI cleanup adds about 0.2–1 s with either approach.

## 7. Design takeaways for our own app (cloud-first, low memory)

1. Stream audio while the user talks; never upload after release.
2. Open the connection on keypress or earlier (HeyClicky). Queue audio until it is ready.
3. Keep a 300–500 ms rolling buffer with a user-chosen warm-mic timeout (EnviousWispr PR #86).
4. Keep the start sound out of the recording rather than erasing it afterwards (Spokenly).
5. Stream from memory; do not save to a file and poll it every 100 ms (Spokenly).
6. Fall back to uploading the whole recording when streaming fails (HeyClicky, Spokenly).
7. Send context such as app name, surrounding text and vocabulary (HeyClicky).
8. Leave AI cleanup off by default or make it on demand.
9. For hands-free mode, run a tiny local speech detector (Silero, a few MB) and send audio only when speech is present. Cut chunks at short pauses and drop noise-only chunks (Hot Mic).
10. Optional offline backup: Moonshine at about 100–150 MB.

## Open work

- Measure memory (idle, dictating, unloaded) and release-to-text latency for the candidates. Use 20 or more repeated trials and report distributions. Run heavy work on endgame.
- Check whether Handy and FluidVoice clip the first word (not yet checked).
- Measure HeyClicky latency and its pre-roll behavior (see the HeyClicky open work).
