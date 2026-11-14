HEYCLICKY REVERSE ENGINEERING
Investigation date: 2026-11-10
Status: streaming model verified; latency and pre-roll investigation open.

VERIFIED RESULT
HeyClicky sent models/gemini-3.5-transcribe-live in outgoing client WebSocket JSON to generativelanguage.googleapis.com at:
/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained
This is a runtime observation, not a guess from product documentation. Four retained proxy flow objects yielded the same model. They should not be treated as four independent benchmark trials. See evidence/live-model-evidence.json for timestamps and attribution.

TARGET IDENTITY
Installed app: /Applications/HeyClicky.app
Executable: /Applications/HeyClicky.app/Contents/MacOS/HeyClicky
Version: 1.1.3 (71), native Swift, universal Mach-O; ARM64 analyzed.
Bundle identifier: com.humansongs.clicky
Configured CodexWorkerBaseURL: https://api.heyclicky.com
Executable SHA-256: 10da0d2641c6d235a57e8b4f2388bcb029e8282aca996f644e264fc6db97e512
Downloaded DMG: /Users/raza/Downloads/HeyClicky.dmg
DMG SHA-256: 532e426c2415384391e01d3a492207c59b06256ae72f8309f44f9831e8b92d4d
The installed app and DMG were identified separately. Exact equality of the installed executable and the DMG's executable was not verified.

FLOW AND EVIDENCE STRENGTH
1. A dedicated DictationGeminiTranscriber wraps OneBrainGeminiTranscriber. Constructor calls were traced in Hopper pseudocode.
2. The dictation session URL ends in /v2/dictation/gemini-token. Its construction was decompiled.
3. Response parsing reads access_token, setup, and receipt. The setup object is cast to a dictionary and serialized under a setup key. The connection request uses an Authorization value with a Token prefix. The server therefore supplies the setup object; the observed live model is above.
4. Audio conversion components and diagnostics reference PCM16. This means 16-bit pulse-code modulation. Exact sample rate, channel count on the dictation path, and chunk duration have not been verified.
5. Embedded diagnostics explicitly describe streaming failure leading to batch fallback, and cleanup failure leading to insertion of raw streamed text. These diagnostics support intended branches; those failure branches were not deliberately exercised.
6. Cached responses establish that this installation contacted /v2/dictation/transcribe and /v2/dictation/cleanup. Both responses contained text and raw_text fields. Transcript values were not copied. Exact backend models for batch transcription and cleanup remain unknown.
7. Insertion-related diagnostics describe focus validation, late focus recapture, clipboard fallback, and refusal of blind paste during secure event input. Accessibility keys include AXFocusedUIElement, AXValue, AXSelectedText, and AXSelectedTextRange. Full insertion control flow was not decompiled.
8. DictationCustomVocabulary and DictationCorrectionLearner are present. Request-related strings include known_terms, app_name, before_text, selected_text, after_text, single_line, and site_host. Their precise inclusion conditions and limits are not verified.

DO NOT CONFUSE THESE WITH DICTATION
The executable contains gemini-3.8-flash-lite-tts in a voice-output context. It is not the verified dictation model.
AppleSpeechTranscriptionProvider and OpenAI realtime transcription event names are also present. Presence does not establish selection for ordinary dictation.
No conclusion about server-side retention of recordings is supported.

STATIC CODE MAP (ARM64 VIRTUAL ADDRESSES)
0x1021c1ccc: builds /v2/dictation/gemini-token URL.
0x1021c1de8: URL accessor; callers include 0x1021c1e38 and 0x1021cb314.
0x1021cb314: passes URL and configuration into 0x1027d87f4.
0x1027d87f4 -> 0x1027d8b04: allocates/initializes dictation wrapper.
0x1027d8b04 -> 0x1016298cc -> 0x101629990: constructs OneBrainGeminiTranscriber.
0x101626358: defines Google constrained bidirectional WebSocket endpoint.
0x10163044c: token response parser and setup serialization; full recovered pseudocode retained.
String addresses: /transcribe 0x1032e0640; /cleanup 0x1032e0660; /gemini-token 0x1032e0680; Google WebSocket URL 0x1032ad090.
These addresses apply only to the identified build. Pseudocode is decompiler output, not original source, and contains imperfect recovered registers/types.

LATENCY AND PRE-ROLL — OPEN WORK
User asks how fast dictation is and whether words immediately after keypress are missed.
No controlled latency measurement has been completed. Do not infer elapsed milliseconds from proxy connection events or transcript archive timestamps.
Observed strings/fields:
- release_to_insert_ms, cleanup_ms, transcript_wait_ms
- dictation_completed, used_batch_fallback, used_warm_connection
- WarmStreamingConnection, warmStreamingConnection
- pressStartedAt, pressStartedWarm, tokenReadyAt, readyAt, firstTextAt, finishCalledAt, finalReceivedAt
- pendingAudio, pendingAudioAppendChunks, pendingAudioAppendChunkSoftCap
- pcm16ChunkHandlerOnStart, accumulatedAudioBuffer
These suggest connection warming, audio queueing, and built-in timing instrumentation. They do not prove audio capture before the keypress.
The selector prerollAtRate:completionHandler: occurs in the binary, but its caller and purpose were not established. It must not be cited as evidence of microphone pre-roll.
Need distinguish three intervals: keypress to first microphone sample; microphone samples buffered while networking starts; key release to final text insertion. A warmed network connection is not microphone pre-roll.
Next work: inspect focused capture-start functions and read timing instrumentation; then a controlled test with known first-word timing, cold/warm starts, and repeated trials. Preserve microphone/device, input method, app version, duration, fallback status, and trial count. Report distributions rather than one anecdotal number.
Heavy analysis must run on endgame, per current user instructions; do not repeat full-app Hopper analysis on this Mac. Worker notes read from ~/Projects/terminal/notes/endgame.md. First ssh attempt failed locally with 'No user exists for uid 501', before connecting. No worker job launched.

METHODS, FAILURES, AND RECOVERY
REA opened and hashed the artifacts. Its Hopper launcher initially failed because Spotlight was disabled. A temporary /Applications symlink fixed discovery, but LaunchServices failed; the REA session also became cleanup-blocked.
Hopper was instead controlled through its UI and Python console. Whole-app analysis/decompilation reached 19.58 GB and caused macOS memory pressure. Hopper was terminated and verified gone. Do not repeat this approach.
A focused LLVM disassembly works with an extracted ARM64 Mach-O and generic -d --start-address/--stop-address. Passing --arch=arm64 on the universal file activated a path that emitted huge disassembly despite range arguments; avoid it.
Frida 17.26.2 attachment failed in the agent shell and user Terminal, including sudo. Hardened runtime was observed, but the precise denial cause was not proven. SIP was not disabled and HeyClicky was not re-signed.
mitmproxy 11.0.2 on Python 3.11 repeatedly failed with broken-pipe/local-helper errors. A Python 3.14 environment with mitmproxy 12.3.1 ran successfully.
Initial app-name capture/filtering did not yield model output. Capture was changed to the exact HeyClicky PID (30777 at the time). Local capture represented a request host by IP; matching request.host against DNS names incorrectly skipped it. Host identity should consider client TLS server name and request.pretty_host.
Model evidence was recovered without another test by inspecting HTTPFlow objects already retained in the proxy process, parsing response JSON and client WebSocket messages for model/model_name/model_id fields. Credentials, audio, and transcript bodies were not written to the evidence file.

CLEANUP STATUS
Capture and Hopper processes were stopped and verified absent. System proxy query returned an empty configuration. Task temporary files, extracted binary, Python environments, capture scripts, certificate private keys, and the stale REA bootstrap directory were deleted. The temporary Hopper symlink was removed.
The agent could not reliably access the user's keychain. User ran certificate deletion; it reported no matching certificate in the login keychain. User subsequently stated 'ok we're good. i switched it off', confirming the network extension was disabled. Certificate absence was not independently established by a reliable agent keychain read.
Temporary CA SHA-1 fingerprint: 94036D61CDBC2F22BE6292A135A33E3FC764D9AD (public identifier, not a secret).
No proxy/certificate should be re-enabled for the latency task without a new justified plan.

FILES
README.txt: current authoritative synthesis.
evidence/live-model-evidence.json: redacted runtime observations.
evidence/token-parser-arm64-0x10163044c.txt: saved Hopper pseudocode.
history/: preserved earlier notes. They contain superseded unknowns and stale process/setup status; use this README for current conclusions.

Workspace note: the requested directory was empty and had no .git metadata when these notes were added. No repository was initialized and no commit was made.

FULL-APP COVERAGE AUDIT (2026-11-10)
Current package inventory: evidence/package-inventory.json records 288 files, 368586663 bytes, SHA-256 per file, and non-key bundle configuration. Version remains 1.1.3 (71). Key/DSN configuration fields omitted. This inventory establishes artifact coverage, not code behavior.
Remaining scope: enumerate all feature entry points; map native subsystems and bundled helpers/frameworks; recover persistence schemas and settings; trace authentication, API contracts, updates, telemetry, audio, screen/context collection and insertion; corroborate runtime-dependent behavior; assemble reconstruction specification with evidence and explicit unknowns. Server implementation cannot be recovered from client artifacts alone.
Worker access rechecked: ssh endgame still exits 255 with No user exists for uid 501 before connection. No remote job started. Continue lightweight package analysis and resolve local SSH execution context before heavy analysis.

Additional reports: component-map.txt covers package subsystems and symbol recovery; drawing-contract.txt covers the shipped JavaScript bridge; browser-protocol.txt documents verified ARM64 framing and its asymmetric input/output length bounds. Detailed disassembly and symbol evidence is under evidence/. Native and server coverage remains incomplete.

USER CONSTRAINT — OFFLINE INVESTIGATION
User explicitly prohibits logged-in requests that could reveal reverse engineering. Continue with local artifacts and retained evidence; do not use account sessions, tokens/cookies or drive HeyClicky/helpers in ways that generate network traffic. Endgame SSH remains authorized for compute only.

WORKER RECOVERY
Endgame SSH now succeeds after resume. Launched browser helper ARM64 decompilation in remote tmux session heyclicky-browser. Input: /home/raza/worker/projects/heyclicky/binaries/browser-host-arm64. Reports/log: /home/raza/worker/projects/heyclicky/reports/browser-host/. Inspect live process and log before restarting; do not infer completion from tmux existence alone. Only compute SSH traffic used; offline account restriction remains active.

WORKER MAIN ANALYSIS
Browser helper analysis completed and pseudocode/log retrieved to evidence/ghidra-browser/. Ghidra reported successful analysis and export, with two external-block decompilation warnings; this is not complete semantic verification. Main app ARM64 slice transferred to endgame with matching SHA-256 checked. Launched tmux heyclicky-main with worker-decompile; output/log at /home/raza/worker/projects/heyclicky/reports/main/. Revalidate live process and log before any restart.
