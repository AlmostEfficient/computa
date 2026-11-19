import SwiftUI

/// The main window: what Computa can do right now, which hotkey it listens for,
/// and a live feed of every key event the tap sees.
struct SettingsView: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    hotkeySection
                    dictationSection
                    permissionsSection
                    testSection
                }
                .padding(20)
                .frame(width: 340, alignment: .topLeading)
                Divider()
                KeyFeed(model: model)
                    .frame(width: 380)
            }
        }
        .frame(height: 720)
        .onAppear { NSApp.activate() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(model.recording ? Color.pink : model.ready ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(model.status).font(.system(size: 13, weight: .medium)).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var hotkeySection: some View {
        Section2("Push-to-talk hotkey") {
            HStack {
                Text(model.recordingHotkey ? "Press keys…" : model.hotkeyName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.recordingHotkey ? Color.pink.opacity(0.18) : Color.secondary.opacity(0.12)))
                Spacer()
                if model.recordingHotkey {
                    Button("Cancel") { model.cancelHotkeyChange() }
                } else {
                    Button("Record…") { model.changeHotkey() }.keyboardShortcut(.defaultAction)
                }
            }
            Picker("", selection: Binding(get: { model.toggleMode }, set: { model.toggleMode = $0 })) {
                Text("Hold to talk").tag(false)
                Text("Press to toggle").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(model.recordingHotkey
                 ? "Press a key or combination, or press and release a lone modifier (Right ⌥, Fn…). Esc cancels."
                 : model.toggleMode ? "Press once to start, press again to stop and insert." : "Hold it to dictate, release to insert.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("Presets:").font(.caption).foregroundStyle(.secondary)
                Button("⌃⇧ Page Down") { model.setHotkey(.ctrlShiftPageDown) }
                Button("Right ⌥") { model.setHotkey(.rightOption) }
                Button("Fn") { model.setHotkey(HotkeyBinding(keyCode: 63, modifiers: 0, isModifier: true)) }
            }
            .controlSize(.small)
        }
    }

    private var dictationSection: some View {
        Section2("Dictation") {
            Text("Vocabulary — one per line, `Term: misheard, misheard`").font(.system(size: 12, weight: .medium)).padding(.top, 4)
            TextEditor(text: Binding(get: { model.vocabularyText }, set: { model.vocabularyText = $0 }))
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))

        }
    }

    private var permissionsSection: some View {
        Section2("Permissions") {
            PermissionRow(title: "Microphone", detail: "To hear you", granted: model.micGranted) { model.requestMicrophone() }
            PermissionRow(title: "Input Monitoring", detail: "To see the hotkey", granted: model.inputMonitoringGranted) { model.requestInputMonitoring() }
            PermissionRow(title: "Accessibility", detail: "To type text and block the hotkey from apps", granted: model.accessibilityGranted) { model.requestAccessibility() }
            HStack {
                Text("Key listener").font(.system(size: 12))
                Spacer()
                Text(model.tapMode.rawValue).font(.system(size: 11)).foregroundStyle(model.tapMode == .active ? .green : model.tapMode == .none ? .red : .orange)
                Button("Reinstall") { model.reinstallTap() }.controlSize(.small)
            }
            if model.setupFailed { Button("Retry microphone setup") { model.retrySetup() }.controlSize(.small) }
            Text("After granting in System Settings, macOS may need Computa relaunched.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var testSection: some View {
        Section2("Test") {
            HStack {
                Button(model.recording ? "Stop" : "Start dictation") { model.recording ? model.keyUp(nil) : model.keyDown(nil) }
                    .disabled(!model.ready)
                Button("Timing log") { NSWorkspace.shared.open(model.telemetry.url) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

private struct Section2<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct PermissionRow: View {
    let title: String, detail: String, granted: Bool
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant") { action() }.controlSize(.small) }
        }
    }
}

private struct KeyFeed: View {
    let model: AppModel
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LIVE KEY EVENTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.keyLog.removeAll() }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if model.keyLog.isEmpty {
                VStack(spacing: 6) {
                    Text(model.tapMode == .none ? "Not listening to keys" : "Press any key")
                        .font(.system(size: 13, weight: .medium))
                    Text(model.tapMode == .none ? "Grant Input Monitoring or Accessibility." : "Every key event Computa sees shows up here. Rows that started or stopped dictation are highlighted.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.keyLog) { event in
                            HStack(spacing: 8) {
                                Text(Self.time.string(from: event.time)).foregroundStyle(.secondary)
                                Text(event.kind).frame(width: 44, alignment: .leading).foregroundStyle(.secondary)
                                Text(event.modifiers + event.key).fontWeight(.medium)
                                Spacer()
                                Text("code \(event.keyCode)").foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(event.matched ? Color.pink.opacity(0.18) : .clear)
                        }
                    }
                }
            }
        }
    }
}
