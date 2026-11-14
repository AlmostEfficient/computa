# Spokenly 2.35.6 (build 645): what happens to the first 500 ms

## The important finding

The ordinary Mac microphone dictation path starts a new AVAudioRecorder on demand.
I found no app-level pre-roll buffer that recovers sound from before recording starts.
Recording begins before the start cue: the app checks microphone levels every 30 ms
and requests the cue once input looks live.

There is a separate, consequential operation AFTER recording: StartCueSilencer can
replace the detected start-sound interval with silence in the recorded WAV file.
It does not separate speech from the sound. Speech in that interval is also erased.
This is conditional, not a blanket discard of the first 500 ms.

For a detected cue starting 100 ms into the recording, the bundled roughly 235 ms
reference plus padding produces an illustrative mute interval of about 85–455 ms.
These times are relative to the recording, NOT to the button press. Actual device
startup latency and acoustic playback timing were not measured.

Practical implication: disabling the start sound bypasses this cue-erasure stage
(the finish path checks playSound). That removes this particular cause of lost
opening speech; it cannot recover speech that was never captured during device startup.

## Startup and capture

1. A new recording session constructs AVAudioRecorder, calls prepareToRecord(), then
   record(). The two inspected start paths do this at 0x1004f560c/0x1004f5614 and
   0x1004f811c/0x1004f8124. Existing recording-session state is reset when necessary.
2. Metering starts after record(). Its timer interval is 0.03 seconds.
3. The first meter reading satisfying power + 120 >= 4 (power >= -116 dB) fires
   onRecordingSignalLive once. This is a signal-availability check, not speech detection.
4. The dictation callback requests the start sound through ShortcutUserFeedbackService,
   subject to current state and playSound. AudioServicesPlaySystemSoundWithCompletion
   performs playback. Capture is already active by this point.
5. There is no fixed 500 ms discard/wait in these inspected microphone start paths.
   The app does not explicitly prepend captured pre-button samples here.

## What StartCueSilencer actually does

The finishRecording path (function 0x1004f3204) reads appStorage.playSound at
0x1004f43f8–0x1004f444c. If enabled, it awaits 0x1007898f4, which loads/caches the
bundled start.mp3 reference and dispatches the file operation at 0x10078b958.
The only direct caller of the public async entry found in executable code is this
finish path. This is post-recording file processing, not the live-stream read loop.

The relevant algorithm, reconstructed from machine code:

```
reference = decode start.mp3 at 16,000 samples/second
referenceSpectrum = power spectrum of a Hann-windowed reference
cueBands = strongest frequency bins accounting for 85% of reference energy

require a recognizable WAV with sampleRate=16000, bitsPerSample=16, channels=1
read up to 65536 bytes from the beginning of the file
find the WAV data chunk
prefix = first min(availableSamples, reference.count + 9600) samples
require prefix.count > reference.count

match = highest absolute normalized waveform correlation with reference
        over all complete reference-sized windows in prefix
require match.score >= 0.5
require match.startSample >= 800
require matched-window energy fraction in cueBands >= 0.5

begin = max(0, match.startSample - 240)
end   = min(availableSamples, match.endSample + 1920)
seek(dataOffset + begin * 2)
write zero-filled Data(count: (end - begin) * 2)
```

Thus the search permits cue starts up to 600 ms into the recording; the best match
is rejected if it starts before 50 ms. The padding is 15 ms before the match and
120 ms after its end. If the waveform or frequency checks fail, it leaves the
recorded audio alone. It preserves file length/time positions by writing zeros;
it does not cut the segment out, subtract only the cue, or preserve overlapping speech.
The search selects the best match before the 50 ms rejection; it does not necessarily
fall back to a second-best later match.

The supplied start.mp3 is mono, 44.1 kHz, about 235.102 ms by afinfo. An independent
Core Audio decode/resample with afconvert produced 3761 mono samples at 16 kHz
(235.063 ms). That is an approximate reference-length illustration, not a runtime
measurement of the app's own decoder or the speaker/microphone acoustic response.

## Live streaming versus finished-file transcription

The manager streams by reading newly appended bytes from the recording file, using
lastProcessedBytes, and polling on a 100 ms sleep. That is delivery cadence, not a
100 ms microphone pre-roll or discarded prefix.

OnlineStreamingAudioTranscriptionService checks connection/provider readiness.
When not ready, it appends incoming audio to pendingAudioData. When ready, it combines
pending bytes with the next chunk before sending. The send path has a 0.45-second
chunk-size calculation (sampleRate * 0.45 * 2 bytes), which should not be confused
with a first-450-ms suppression window.

The traced live read/send path does not call StartCueSilencer. Audio already sent
live cannot be retrospectively changed by a later edit to the saved file. Therefore
live-recognition input and the finished file can differ around the cue. A fallback
that transcribes the completed file can use the edited file; the binary contains
and uses the 'Stream never became ready, transcribing the recorded file instead'
branch. Provider-specific recognition and silence handling can add further differences.

## Evidence ledger (addresses are unslid ARM64 virtual addresses)

### E1 — Target identity
```
Input: /Users/raza/Downloads/Spokenly-2.35.6.dmg
DMG SHA-256: d3f59582118b25920312fe118efd6afa9ec52675ee0e0a7ff0639ba27866d42f
Extracted ARM64 executable SHA-256:
  cef14eb7d24ecbd16197d151775a1f04758d30d19a8ebd3e2b5c26c96281fc0d
Contents/Info.plist reports 2.35.6 and build 645.
The package is universal x86_64 + ARM64; behavioral analysis here used ARM64.
```

### E2 — Start and cue ordering (startup-annotated.asm, startup-findings.txt)
```
prepare/record: 0x1004f560c/0x1004f5614 and 0x1004f811c/0x1004f8124
meter setup: 0x1004f62ec; 0.03 constant 0x1004f6434–0x1004f6444
signal callback: 0x1004fa8ec; invocation 0x1004fa9d0
callback wiring: 0x100712a44–0x100712a60; closure 0x10072351c
feedback: 0x100715080; start request 0x100715448
system sound API: 0x100782e88
```

### E3 — Finish-only call and setting (recording-annotated.asm)
```
0x1004f43f8–0x1004f44c0: playSound conditional then async silencer call.
ObjC/Swift ivar metadata identifies appStorage at 0x100e6aaa8,
startCueSilencer at 0x100e6aab0, and _playSound at 0x100e7c358.
```

### E4 — Erasure algorithm (silencer-annotated.asm)
```
0x10078a3d4: reference loading/conversion and reference preparation
0x10078a368: sample rate constant 16000.0
0x10078b154: reference spectrum and 85% energy-bin selection
0x10078b500: matched-window energy fraction
0x10078b6b4: normalized absolute correlation, threshold 0.5
0x10078b958: file operation
0x10078bb14–0x10078bb38: WAV format tuple check
0x10078bc2c–0x10078bc80: 0.6 seconds plus reference length
0x10078be48–0x10078be9c: 0.05 seconds minimum match offset
0x10078bf10–0x10078bf18: frequency-energy fraction >= 0.5
0x10078bf34–0x10078c000: 0.015/0.12 padding and bounds
0x10078c010–0x10078c078: byte offset, seek, zero-data construction, write
0x100025474: zero-initialized Data length helper (support-annotated.asm)
0x1005f82e0: WAV sample-rate/bits/channels parser (support-annotated.asm)
```

### E5 — Live streaming (recording-annotated.asm, network-annotated.asm)
```
0x1004f7164: incremental file reader; seek/read at 0x1004f75e0/0x1004f75ec
0x1004f6910–0x1004f692c and 0x1004f6abc–0x1004f6ad0: 100,000,000 ns sleep
0x1006e8f28: connection/readiness branch and pending-audio handling
0x1006e9074–0x1006e9118: append before ready
0x1006e9160–0x1006e91a8: combine pending + current then clear pending
0x1006e8b70: Data concatenation helper (support-annotated.asm)
0x1006e8fd4–0x1006e8fe8: 0.45 * sampleRate * 2 chunk-size calculation
```

## Scope and confidence

The startup ordering, constants, branches, file writes, and queue operations are
supported by disassembly, imported API names, Objective-C selector decoding, and
Swift stored-property metadata. The report translates those instructions into
higher-level behavior; it is not recovered original source.

No app execution, microphone recording, cloud request, or user-setting change was
performed. No claim is made about measured hardware latency, how often cue detection
succeeds with speech mixed in, every recognition provider, phone/meeting recording,
or equivalence of the unexamined x86_64 implementation. The absence of pre-button
buffering is bounded to the traced primary local-microphone dictation implementation.
Recognizer-side fields such as rescueSpanPreRollFrames occur in the bundled
FluidAudio streaming recognizer; their names do not establish pre-button capture.

Tools: read-only hdiutil mount; lipo; strings; nm; otool disassembly and metadata;
Capstone on endgame; independent instruction/constant/call checks; afinfo/afconvert.
REA registration diagnostics succeeded, but REA MCP tools were absent in this session;
ordinary tool output above is not REA Evidence. A broad Ghidra pass was started as
an optional aid; conclusions do not rely on that incomplete pass.

## Transcription providers in the build (from the class-name dump)

Source: Swift class names in `metadata.txt` from `~/Downloads/Spokenly-2.35.6-analysis` (an otool Objective-C metadata dump). A class being present shows that the provider is supported in code. It does not show which provider is the default or what each one costs.

- **Cloud streaming handlers:** Deepgram, AssemblyAI, ElevenLabs, Cartesia, Gemini Live, OpenAI Realtime, Corti, Sarvam, Volcengine, plus Spokenly's own backend (`SpokenlyV2StreamingHandler`).
- **Cloud, not streaming:** Cohere (`CohereTranscriptionService`), plus a generic `OnlineAudioTranscriptionService`.
- **Local:** Whisper; Parakeet, in unified and EOU (end-of-utterance streaming) variants through FluidAudio; Nemotron Multilingual; Apple Speech; Apple SpeechAnalyzer.
- **Other audio services:** `VadTrimService` (trims silence with a speech detector), speaker diarization, system-audio capture and meeting detection.

Takeaway for a cloud-first design: Spokenly treats the provider as pluggable behind one streaming interface (`OnlineStreamingAudioTranscriptionService`). The streaming providers it ships are a ready shortlist to benchmark.
