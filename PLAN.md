# Computa dictation: build plan

Drafted 2026-11-14 from `research/` (HeyClicky, Spokenly, dictation comparison) and the follow-up research on capture start-up.

**Goal:** a native macOS dictation app that transcribes in the cloud, keeps the first word, uses tens of MB of memory when idle, and inserts text about 150–400 ms after you release the key.

**Rule for every phase:** no performance claim without a measurement. Every phase ends with numbers from the timing harness (phase 1), with distributions over 20 or more trials, cold and warm.

## Constraints

- 16 GB Mac, usually full of Chrome. No resident local speech model (about 500 MB or more is ruled out).
- Apple Speech is ruled out for accuracy.
- The mic is **off when idle** by default. Warm mic is opt-in.
- Heavy work (model evaluation, batch benchmarks) runs on endgame, not this Mac.
- Out of scope for now: everything in HeyClicky beyond dictation (agent loop, browser helper, drawing, routines).

## Architecture

```
 hotkey (CGEventTap)                         Accessibility
   │ key-down / first modifier                 │ context: app, text before/after, selection
   ▼                                           ▼
 AudioCapture ──PCM──▶ SampleQueue ──▶ StreamClient ──WS──▶ ASR provider
 (prepared, paused     (lock-free ring,   (pre-warmed,        (Gemini Live /
  AVAudioEngine +       keeps every        token from          Deepgram / …)
  AVAudioSinkNode)      sample)            our backend)
                            │                  │ final text
                            │                  ▼
                            │              Cleanup (local rules; LLM opt-in)
                            │                  │
                            └─▶ batch fallback ▼
                                           Inserter (AX set → paste + clipboard restore)
```

- **Swift app in the menu bar**, no Electron, Bun or Python. Target idle memory: 60 MB or less.
- One process. Local speech detection (Silero, a few MB) and offline Moonshine run in a child process loaded only on demand, so their memory returns to the OS when they unload (Handy's pattern).
- **Token service:** a tiny backend endpoint that issues short-lived provider tokens (HeyClicky `/v2/dictation/gemini-token` pattern). Audio goes straight from the client to the provider, never through us.

## Implementation status (2026-11-14)

Initial native prototype, configured Gemini Live path, and experimental Deepgram adapter are present. Gemini token issuance and native Swift synthetic-speech transcription have been verified; the personal API key is stored in Keychain. See README.md for build/run instructions and explicit remaining work. Swift unit tests cover ring overflow/wraparound and percentile calculation. No phase exit gate has been measured or passed; unchecked entries below remain authoritative.

## Phase 0: project skeleton (about 1 day)

- [x] Xcode project: menu-bar app (`LSUIElement`), Swift 6, macOS 15+, signing team `V5W4LV96XX`.
- [ ] Modules: `Capture`, `Hotkey`, `Stream`, `Insert`, `Context`, `Telemetry`, `App`.
- [ ] Permission onboarding: Microphone, Accessibility, Input Monitoring (for the event tap). Do all of it before the first hotkey, never during one.
- [ ] `os_signpost` + a local JSONL timing log from day one.

## Phase 1: capture core + timing harness (the foundation)

**Capture lifecycle**
- [ ] Build the graph once: input → `AVAudioSinkNode`. Cache the device ID, hardware format, converter and preallocated buffers.
- [ ] Call `prepare()` at launch. On activation call `start()`; at the end call `pause()`. Never `stop()` on the hot path.
- [ ] Invalidate and rebuild only on device changes (`kAudioHardwarePropertyDefaultInputDevice`, route changes), sleep/wake, or engine configuration-change notifications.
- [ ] Sink callback: copy native-format frames into a preallocated single-producer/single-consumer ring. No allocation, locks, dispatch or I/O.
- [ ] Off the real-time thread: convert to 16 kHz mono PCM16 and timestamp every chunk with host time.
- [ ] Input choice: prefer the built-in or a wired mic even when Bluetooth headphones are the output. Never prepare a Bluetooth input while idle (it can hold the headset in call mode).

**Hotkey**
- [ ] `CGEventTap` on `keyDown`/`keyUp`/`flagsChanged`. The callback only stamps the time and signals; no work on the tap thread.
- [ ] Capture starts on the **down edge**. Tap-versus-hold mode is decided *after* capture has started (provisional capture).
- [ ] No start sound in the capture path. Use a visual indicator (menu-bar or notch overlay) that renders after capture has started.

**Timing harness** (the first thing to build)
- [ ] Measure three intervals separately: key event → `start()` returns; key event → first sink callback; key event → first *real* acoustic sample.
- [ ] Measure the acoustic onset with a known reference: a speaker plays a click or chirp at a scripted time relative to a synthesised key event. Cross-correlate it against the capture.
- [ ] Runs: 20 or more trials each × {cold after launch, paused after an earlier use, after sleep/wake} × {built-in mic, wired, Bluetooth}.
- [ ] Output: p50/p90/p99 per interval, written to `bench/capture-*.jsonl` plus a summary script.

**Exit:** the key-event → first-real-sample distribution is known for each route, and paused-start p50 is measurably below cold-start p50.

## Phase 2: provider benchmark (the first real decision)

- [ ] `StreamingTranscriber` protocol: `connect()`, `send(pcm)`, `finish() async -> Final`, `cancel()`, partial-results stream. One protocol for all providers (Spokenly's pattern).
- [ ] Adapters: Gemini `transcribe-live` (proven in HeyClicky), Deepgram, AssemblyAI, OpenAI Realtime. ElevenLabs and Cartesia if time allows.
- [ ] Test set: 50 or more recorded utterances (short commands, 5–15 s prose, names and jargon, code terms). Make variants with the start cut off at 25/50/100/150 ms after speech onset.
- [ ] Replay at real-time pace through each adapter from endgame and from this Mac (to see the network differences).
- [ ] Metrics per provider: **release → final text** (p50/p90), time to first partial, whole-utterance error rate, **first-word accuracy** on the truncated set, wrongly inserted words with vocabulary boosting on, and cost per hour.

**Exit:** a chosen default provider plus a fallback, with a results table in `bench/providers.md`.

## Phase 3: streaming path

- [ ] Pre-warm: open the TLS socket and send setup at launch, and again after wake or a network change. Refresh the token before it expires. Use keepalives as each provider requires.
- [ ] On key-down, capture and the connection run **independently**. The queue keeps every sample from the first one and flushes the backlog in order once the connection is ready. The network never decides which samples survive.
- [ ] Context: on key-down, collect the app name, text before and after the cursor, the selection and vocabulary through AX, in parallel. Send it with the setup or the first message where the provider allows.
- [ ] Release: send finalise or end of stream, await the final result, with a timeout.
- [ ] Fallback: if streaming fails or times out, upload the in-memory recording to the batch endpoint. If that fails too, show the partial text on the clipboard.
- [ ] Escape cancels and discards late results.

**Exit:** release → insert-ready text at p50 of 400 ms or less on home Wi-Fi, warm, with every fallback branch exercised on purpose.

## Phase 4: insertion

- [ ] First choice: `AXUIElementSetAttributeValue` on `kAXSelectedTextAttribute` of the focused element. Check that focus hasn't changed since key-down.
- [ ] Fallback: save the pasteboard, write the text, post ⌘V, restore the pasteboard after a short delay. Skip it during secure input and show "Copied, press ⌘V" instead (HeyClicky's pattern).
- [ ] Empty or whitespace result: insert nothing and leave the clipboard alone.
- [ ] Test matrix: Chrome text area, Google Docs, Slack, VS Code, Terminal, Notes, Mail, Xcode.

## Phase 5: cleanup and vocabulary

- [ ] Local rules at no extra latency: filler words, spacing, capitalisation, spoken punctuation.
- [ ] Custom vocabulary list, sent as provider keyterms or phrase hints. Measure wrongly inserted words; stronger boosting can add words nobody said.
- [ ] LLM cleanup: opt-in, streamed, skipped for utterances under N words. If it fails, insert the raw text.

## Phase 6: first-word hardening

- [ ] **Experiment: start on the first modifier.** Begin capture on the first modifier of the shortcut (for example Right Option) and keep the audio in RAM. Commit when the shortcut completes; discard on a different key, on release or after about 300 ms. Measure how often it gives enough lead time (lead ≥ capture gap + how early the user starts talking) and how often the mic opens for nothing.
- [ ] **Warm mic (opt-in):** keep capture running for 10/30/60 s after a dictation, or always, with a 500 ms pre-roll in front of the next press (EnviousWispr PR #86). Document the orange indicator and the Bluetooth effects in settings.
- [ ] **Suspicious-start detector:** RMS plus a speech detector on the first 100–200 ms. If speech was already underway at the start, optionally re-decode with context or show "may have missed the start".
- [ ] Weak signals (focus moved into a text field, a pause in typing) only pre-warm the connection. They never open the mic.

## Phase 7: optional offline fallback

- [ ] Moonshine (about 100–150 MB) in a child process, loaded on demand, unloaded after an idle timeout. Used only when the network is down.

## Measurement budget (fill in as phases land)

| Metric | Target | Measured |
|---|---|---|
| Idle memory (RSS) | ≤ 60 MB | |
| Key-down → first real sample, paused engine | as low as the hardware allows; baseline from phase 1 | |
| Key-down → first sample, cold | baseline from phase 1 | |
| Release → text inserted, warm socket, p50 | ≤ 400 ms | |
| Release → text inserted, cold socket, p50 | ≤ 700 ms | |
| First-word accuracy, start cut by 50 ms | baseline from phase 2 | |
| Idle CPU wakeups | ≈ 0 while the mic is off | |

## Open questions

- Is the remaining start-up gap after `pause()` the hardware or our code? Phase 1 answers this.
- Which provider gives the lowest release → final time from where you actually dictate? Phase 2.
- Does preparing a paused engine on a Bluetooth input trigger call mode on the user's headsets? Phase 1 route matrix.
- Lifetime and refresh rules for each provider's token and socket (idle timeouts) for the pre-warm.
- Claims not verified yet: TapTalk's 98 → 50 ms, MacParakeet's Bluetooth suppression, Handy's caching gains.
