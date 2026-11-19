import SwiftUI
import AVFoundation
@preconcurrency import ApplicationServices

@main struct ComputaApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("Computa", id: "main") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        MenuBarExtra("Computa", systemImage: "character.cursor.ibeam") {
            MenuContent(model: model)
        }
    }
}

private struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Text("Hotkey: \(model.hotkeyName)")
        Divider()
        Button("Open Computa…") { openWindow(id: "main"); NSApp.activate() }
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

@MainActor @Observable final class AppModel {
    var status = "Set up permissions before capturing" { didSet { FileHandle.standardError.write(Data("status: \(status)\n".utf8)) } }
    var recording = false
    var hotkeyName = HotkeyBinding.load().name
    var recordingHotkey = false
    /// Press once to start, press again to stop (instead of hold-to-talk).
    var toggleMode = UserDefaults.standard.bool(forKey: "toggleMode") {
        didSet { UserDefaults.standard.set(toggleMode, forKey: "toggleMode"); if ready { status = idleStatus } }
    }
    var idleStatus: String { toggleMode ? "Press \(hotkeyName) to start, again to stop" : "Hold \(hotkeyName) to dictate" }
    var keyLog: [KeyEventRecord] = []
    var tapMode = Hotkey.TapMode.none
    var micGranted = false
    var accessibilityGranted = false
    var inputMonitoringGranted = false
    var setupFailed = false
    var ready = false
    let telemetry = Telemetry()
    /// Launch with `-measureOnly YES` to time capture without any network or insertion.
    let measureOnly = UserDefaults.standard.bool(forKey: "measureOnly")
    private let capture = AudioCapture()
    private let hotkey = Hotkey()
    private let pool = GeminiWarmPool()
    private var keyHost: UInt64 = 0
    private var eventToTapMS: Double?
    private var startReturnMS = 0.0
    private var used = false
    private var finishing = false
    private var session: GeminiTranscriber?
    private var wasWarm: Bool?
    private var sendTask: Task<Void, Error>?
    private var drainTask: Task<Void, Never>?
    private var audio = Data()   // 16 kHz PCM16 of this dictation (32 kB/s), kept for replay if streaming fails
    private var focus: Focus?
    private var selfTesting = false
    private let overlay = OverlayController()
    /// Bumped on every new dictation and on cancel; late async work for an older one is discarded.
    private var generation = 0

    /// One entry per line: `Term` fixes its capitalisation; `Term: misheard, other misheard` also
    /// replaces those phrases with the term. Applied locally to the final text.
    var vocabularyText = UserDefaults.standard.string(forKey: "vocabulary") ?? "Computa\nGhostty: Ghosty, Ghostwriter" {
        didSet { UserDefaults.standard.set(vocabularyText, forKey: "vocabulary") }
    }
    var vocabulary: [VocabularyEntry] { VocabularyEntry.parse(vocabularyText) }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.ready, !self.measureOnly { self.pool.warm() } }
        }
        overlay.model.onCancel = { [weak self] in self?.cancel() }
        // The hotkey works (and the key feed shows events) independently of microphone setup.
        hotkey.onEvent = { [weak self] record in
            guard let self else { return }
            keyLog.insert(record, at: 0)
            if keyLog.count > 40 { keyLog.removeLast(keyLog.count - 40) }
        }
        hotkey.setHandler { [weak self] edge in
            guard let self else { return }
            guard self.ready else { if edge.down { self.status = "Hotkey detected, but the microphone isn't set up yet" }; return }
            if self.toggleMode {
                guard edge.down else { return }   // releases don't matter in toggle mode
                self.recording ? self.keyUp(edge) : self.keyDown(edge)
                return
            }
            guard self.recording != edge.down else { return }
            edge.down ? self.keyDown(edge) : self.keyUp(edge)
        }
        refreshPermissions()
        // Permissions change in System Settings while we run; poll so the window stays truthful
        // and the tap upgrades to active as soon as Accessibility is granted.
        Task { while true { refreshPermissions(); try? await Task.sleep(for: .seconds(1)) } }
    }

    func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        if hotkey.mode != .active && (accessibilityGranted || (hotkey.mode == .none && inputMonitoringGranted)) { hotkey.install() }
        tapMode = hotkey.mode
        if micGranted && !ready && !setupFailed { setUp() }
    }

    func requestMicrophone() {
        Task {
            if await AVCaptureDevice.requestAccess(for: .audio) { setUp() }
            else { Self.openPrivacyPane("Privacy_Microphone") }
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { Self.openPrivacyPane("Privacy_Accessibility") }
    }
    func requestInputMonitoring() {
        if !CGRequestListenEventAccess() { Self.openPrivacyPane("Privacy_ListenEvent") }
    }
    static func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
    func setHotkey(_ binding: HotkeyBinding) {
        hotkey.set(binding); hotkeyName = binding.name
        if ready { status = idleStatus }
    }
    func retrySetup() { setupFailed = false; setUp() }
    func reinstallTap() { hotkey.install(); tapMode = hotkey.mode }

    func permissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { status = "Microphone permission required"; return }
            setUp()
        }
    }

    private func setUp() {
        guard !ready else { return }
        do { try capture.prepare() } catch { setupFailed = true; status = "Microphone setup failed: \(error). Pick a built-in or USB mic, then Retry."; return }
        if !ready && !measureOnly { pool.start() }
        ready = true
        status = idleStatus
        if hotkey.mode == .none && !hotkey.install() { status = "Microphone ready. Grant Input Monitoring for the hotkey." }
        tapMode = hotkey.mode
        if let path = UserDefaults.standard.string(forKey: "dictateTest") { Task { await dictateTest(path) } }
        if let path = UserDefaults.standard.string(forKey: "transcribeTest") { Task { await transcribeTest(path) } }
        if UserDefaults.standard.bool(forKey: "overlayDemo") { Task { await overlayDemo() } }
        let trials = UserDefaults.standard.integer(forKey: "selfTest")
        if trials > 0 { Task { await selfTest(trials) } }
    }

    /// Key-down path. Capture starts first; nothing that can block (Accessibility IPC, actor hops,
    /// session handoff) runs before `capture.start()`.
    func keyDown(_ edge: KeyEdge?) {
        guard !finishing, !recording else { return }
        keyHost = edge?.tapHost ?? mach_absolute_time()
        eventToTapMS = edge?.eventToTapMS
        do { try capture.start() } catch { status = "Start failed: \(error)"; return }
        startReturnMS = Self.ms(since: keyHost)
        recording = true
        generation += 1
        overlay.show()
        telemetry.signposter.emitEvent("CaptureStarted")
        audio = Data(); session = nil; wasWarm = nil
        if !measureOnly {
            status = "Listening…"
            sendTask = Task {
                let taken = await pool.take()
                session = taken.session; wasWarm = taken.wasWarm
                try await taken.ready.value
                try await taken.session.begin()
            }
        } else { status = "Measuring • audio discarded" }
        focus = measureOnly ? nil : Focus.current()
        drainTask = Task { while !Task.isCancelled { pump(capture.drainPCM16()); overlay.model.push(capture.level); try? await Task.sleep(for: .milliseconds(20)) } }
    }

    private func pump(_ pcm: Data) {
        guard !measureOnly, !pcm.isEmpty else { return }
        audio.append(pcm)
        let previous = sendTask
        sendTask = Task { try await previous?.value; try await session?.send(pcm: pcm) }
    }

    func keyUp(_ edge: KeyEdge?) {
        guard recording else { return }
        let releaseHost = edge?.tapHost ?? mach_absolute_time()
        capture.pause(); drainTask?.cancel(); recording = false
        pump(capture.drainPCM16(final: true))
        let first = capture.firstHost
        var trial = Trial(source: edge != nil ? "key" : selfTesting ? "selftest" : "manual", condition: used ? "paused" : "cold", sampleRate: capture.sampleRate,
                          eventToTapMS: eventToTapMS, startReturnMS: startReturnMS,
                          firstCallbackMS: first >= keyHost && first != 0 ? AVAudioTime.seconds(forHostTime: first - keyHost) * 1000 : nil,
                          droppedFrames: capture.dropped)
        used = true
        guard !measureOnly else { log(trial); status = "Saved capture timing"; overlay.hide(); return }
        finishing = true; status = "Transcribing…"
        overlay.model.phase = .transcribing
        let pending = sendTask, audio = audio, focus = focus, session = session, mine = generation
        Task {
            var text: String?
            do {
                try await pending?.value
                guard let session else { throw GeminiError.protocolFailure }
                text = try await session.finish().text
            } catch {
                trace("stream failed: \(error); replaying")
                await session?.cancel()
                if mine == generation { text = try? await Self.replay(audio); trial.fallback = true }
            }
            guard mine == generation else { return }   // cancelled, or a newer dictation owns the state
            finishing = false; self.session = nil; sendTask = nil; self.audio = Data()
            trial.warmSession = wasWarm
            trial.releaseToTextMS = Self.ms(since: releaseHost)
            overlay.hide()
            trace("final text (\(trial.releaseToTextMS.map { Int($0) } ?? -1) ms, warm \(String(describing: wasWarm)), fallback \(trial.fallback == true)): \(text ?? "<none>")")
            status = text.map { Inserter.insert(VocabularyEntry.apply(vocabulary, to: $0), into: focus) } ?? "Transcription failed. Check connectivity and Gemini Keychain access."
            log(trial)
        }
    }

    /// The next key, combination, or lone modifier pressed becomes the push-to-talk hotkey. Esc cancels.
    func changeHotkey() {
        guard !recording else { return }
        recordingHotkey = true
        status = "Press the new hotkey (Esc cancels)"
        hotkey.record { [weak self] binding in
            guard let self else { return }
            recordingHotkey = false
            if let binding {
                hotkeyName = binding.name
                guard ready else { status = "Hotkey set to \(binding.name). Set up the microphone to dictate."; return }
                status = !binding.isModifier && !hotkey.canSwallow
                    ? idleStatus + ". Grant Accessibility so it stops typing into apps."
                    : idleStatus
            } else { status = idleStatus }
        }
    }
    func cancelHotkeyChange() { hotkey.cancelRecording() }

    /// The overlay's X: drop the dictation whether it is still listening or already transcribing.
    func cancel() {
        generation += 1
        if recording { capture.pause(); drainTask?.cancel(); recording = false }
        let session = session
        Task { await session?.cancel() }
        self.session = nil; sendTask = nil; audio = Data(); finishing = false
        overlay.hide()
        status = "Cancelled"
    }

    /// Fallback: a fresh session fed the whole recording, so a dead stream does not lose the dictation.
    private static func replay(_ audio: Data) async throws -> String {
        let session = GeminiTranscriber()
        try await session.connect()
        try await session.begin()
        var offset = 0
        while offset < audio.count {
            let end = min(offset + 32_000, audio.count)   // 1 s per message
            try await session.send(pcm: audio.subdata(in: offset..<end)); offset = end
        }
        return try await session.finish().text
    }

    private func log(_ trial: Trial) {
        do { try telemetry.record(trial) } catch { status = "Log failed: \(error)" }
    }

    /// `-selfTest N`: N start/stop cycles through the same path as the hotkey, then quit.
    /// The first cycle after launch is the "cold" condition.
    private func selfTest(_ count: Int) async {
        selfTesting = true
        try? await Task.sleep(for: .seconds(1))
        for _ in 0..<count {
            keyDown(nil)
            try? await Task.sleep(for: .milliseconds(800))
            keyUp(nil)
            while finishing { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(400))
        }
        NSApplication.shared.terminate(nil)
    }

    /// `-dictateTest file.wav -dictateIdles "0,60"`: the full real path. For each idle gap: wait, start
    /// dictation, play the file out of the speakers so the real mic hears it, stop, insert into the
    /// frontmost app. Results go to stderr and the timing log.
    private func dictateTest(_ path: String) async {
        let idles = (UserDefaults.standard.string(forKey: "dictateIdles") ?? "0").split(separator: ",").compactMap { Double($0) }
        guard let sound = NSSound(contentsOfFile: path, byReference: true) else { trace("cannot load \(path)"); return }
        selfTesting = true
        for idle in idles {
            trace("— idle \(Int(idle)) s, then dictate")
            try? await Task.sleep(for: .seconds(max(idle, 1)))
            keyDown(nil)
            try? await Task.sleep(for: .milliseconds(300))
            sound.play()
            try? await Task.sleep(for: .seconds(sound.duration + 0.8))
            keyUp(nil)
            while finishing { try? await Task.sleep(for: .milliseconds(50)) }
            trace("result: \(status)")
        }
        NSApplication.shared.terminate(nil)
    }

    /// `-transcribeTest file.wav`: 16 kHz mono PCM16 WAV through the warm-session path
    /// (idle 3 s after connecting, like a real keypress), then the replay path. Prints results and quits.
    private func transcribeTest(_ path: String) async {
        guard let wav = FileManager.default.contents(atPath: path), wav.count > 44 else { trace("cannot read \(path)"); return }
        // Find the "data" chunk; `say` and afconvert write extra chunks before it.
        guard let marker = wav.range(of: Data("data".utf8)) else { trace("no data chunk"); return }
        let pcm = wav.subdata(in: (marker.upperBound + 4)..<wav.count)
        let session = GeminiTranscriber()
        let started = Date()
        do {
            try await session.connect(); trace("connected in \(Int(Date().timeIntervalSince(started) * 1000)) ms; idling 3 s")
            try await Task.sleep(for: .seconds(3))
            try await session.begin()
            var offset = 0
            while offset < pcm.count {   // real-time pace, 20 ms chunks
                let end = min(offset + 640, pcm.count)
                try await session.send(pcm: pcm.subdata(in: offset..<end)); offset = end
                try await Task.sleep(for: .milliseconds(20))
            }
            let release = Date()
            let text = try await session.finish().text
            trace("STREAM OK in \(Int(Date().timeIntervalSince(release) * 1000)) ms: \(text)")
        } catch { trace("STREAM FAILED: \(error)") }
        let replayStart = Date()
        do { let text = try await Self.replay(pcm); trace("REPLAY OK in \(Int(Date().timeIntervalSince(replayStart) * 1000)) ms: \(text)") }
        catch { trace("REPLAY FAILED: \(error)") }
        NSApplication.shared.terminate(nil)
    }

    /// `-overlayDemo YES`: shows the pill with a synthetic voice-like level for visual checks, then quits.
    private func overlayDemo() async {
        overlay.show()
        for tick in 0..<150 {
            let t = Double(tick) * 0.02
            overlay.model.push(Float(max(0, sin(t * 7) * 0.5 + sin(t * 2.3) * 0.4 + 0.2)))
            if tick == 110 { overlay.model.phase = .transcribing }
            try? await Task.sleep(for: .milliseconds(20))
        }
        overlay.hide()
        try? await Task.sleep(for: .milliseconds(300))
        NSApplication.shared.terminate(nil)
    }

    private static func ms(since host: UInt64) -> Double {
        let now = mach_absolute_time()
        return now > host ? AVAudioTime.seconds(forHostTime: now - host) * 1000 : 0
    }
}
