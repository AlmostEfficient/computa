import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct KeyEdge {
    let down: Bool
    /// mach_absolute_time() taken first thing in the tap callback.
    let tapHost: UInt64
    /// Delay from the event's own timestamp to the tap callback, when the timestamp is plausible.
    let eventToTapMS: Double?
}

/// A push-to-talk binding: either a lone modifier key (held on its own) or a key with optional modifiers.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: Int64
    /// Required ⌘⌥⌃⇧ (device-independent) for non-modifier keys; ignored for a lone modifier.
    var modifiers: UInt64
    var isModifier: Bool

    static let rightOption = HotkeyBinding(keyCode: 61, modifiers: 0, isModifier: true)
    static let relevantModifiers: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue

    /// Device-dependent flag bit per modifier key, so left and right are told apart.
    static let modifierMasks: [Int64: UInt64] = [
        54: 0x10, 55: 0x08,          // right / left Command
        60: 0x04, 56: 0x02,          // right / left Shift
        61: 0x40, 58: 0x20,          // right / left Option
        62: 0x2000, 59: 0x01,        // right / left Control
        63: CGEventFlags.maskSecondaryFn.rawValue,
    ]

    var name: String {
        if isModifier { return Self.modifierNames[keyCode] ?? "Key \(keyCode)" }
        var parts = ""
        if modifiers & CGEventFlags.maskControl.rawValue != 0 { parts += "⌃" }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { parts += "⌥" }
        if modifiers & CGEventFlags.maskShift.rawValue != 0 { parts += "⇧" }
        if modifiers & CGEventFlags.maskCommand.rawValue != 0 { parts += "⌘" }
        return parts + (Self.keyNames[keyCode] ?? Self.character(for: keyCode) ?? "Key \(keyCode)")
    }
    static func modifierString(_ flags: UInt64) -> String {
        var parts = ""
        if flags & CGEventFlags.maskSecondaryFn.rawValue != 0 { parts += "fn " }
        if flags & CGEventFlags.maskControl.rawValue != 0 { parts += "⌃" }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { parts += "⌥" }
        if flags & CGEventFlags.maskShift.rawValue != 0 { parts += "⇧" }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { parts += "⌘" }
        return parts
    }
    static func keyName(_ keyCode: Int64) -> String {
        modifierNames[keyCode] ?? keyNames[keyCode] ?? character(for: keyCode) ?? "Key \(keyCode)"
    }
    static let ctrlShiftPageDown = HotkeyBinding(keyCode: 121, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, isModifier: false)
    private static let modifierNames: [Int64: String] = [54: "Right ⌘", 55: "Left ⌘", 60: "Right ⇧", 56: "Left ⇧",
        61: "Right ⌥", 58: "Left ⌥", 62: "Right ⌃", 59: "Left ⌃", 63: "Fn"]
    private static let keyNames: [Int64: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        123: "←", 124: "→", 125: "↓", 126: "↑", 121: "Page Down", 116: "Page Up", 115: "Home", 119: "End",
        117: "Forward Delete", 114: "Help"]
    private static func character(for keyCode: Int64) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer in
            UCKeyTranslate(buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress!, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    static func load() -> HotkeyBinding {
        guard let data = UserDefaults.standard.data(forKey: "hotkey"),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return .ctrlShiftPageDown }
        return binding
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "hotkey") }
}

/// One key event as the tap saw it, for the settings window's live feed.
struct KeyEventRecord: Identifiable {
    let id = UUID()
    let time = Date()
    let kind: String      // "down", "up", "repeat", "mod"
    let keyCode: Int64
    let key: String
    let modifiers: String
    let matched: Bool     // this event drove the push-to-talk hotkey
}

@MainActor final class Hotkey {
    enum TapMode: String { case none = "Not installed", listenOnly = "Listen only (can't block keys)", active = "Active (can block keys)" }
    private(set) var binding = HotkeyBinding.load()
    private(set) var mode = TapMode.none
    var onEvent: ((KeyEventRecord) -> Void)?
    /// Escape pressed with no modifiers; return true if it was used (it is then swallowed).
    var onEscape: (() -> Bool)?
    private var swallowEscapeUp = false
    func set(_ binding: HotkeyBinding) { self.binding = binding; binding.save(); held = false }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((KeyEdge) -> Void)?
    private var held = false
    /// Recording a new binding: the next key or lone modifier pressed becomes the hotkey.
    private var recorder: ((HotkeyBinding?) -> Void)?
    private var candidateModifier: Int64?
    private(set) var canSwallow = false

    func setHandler(_ handler: @escaping (KeyEdge) -> Void) { self.handler = handler }
    /// Creates the event tap. Safe to call repeatedly; retries after permissions change.
    @discardableResult func install() -> Bool {
        if tap != nil, mode == .active { return true }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; self.tap = nil; mode = .none }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            let tapHost = mach_absolute_time()
            let tapNanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            guard let context else { return Unmanaged.passUnretained(event) }
            // The tap source is on the main run loop, so this callback is already main-actor isolated.
            // Handle it synchronously: a Task hop would add scheduling delay before capture starts.
            let swallow = MainActor.assumeIsolated {
                Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue().handle(type, event, tapHost: tapHost, tapNanos: tapNanos)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // An active tap (needs Accessibility) can swallow a key hotkey so it doesn't also type;
        // fall back to listen-only (Input Monitoring), which suits lone-modifier hotkeys.
        if let active = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback, userInfo: context) {
            tap = active; canSwallow = true; mode = .active
        } else if let passive = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                                  eventsOfInterest: mask, callback: callback, userInfo: context) {
            tap = passive; canSwallow = false; mode = .listenOnly
        } else { return false }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap!, enable: true)
        return true
    }

    func record(_ done: @escaping (HotkeyBinding?) -> Void) { recorder = done; candidateModifier = nil; held = false }
    func cancelRecording() { recorder?(nil); recorder = nil }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent, tapHost: UInt64, tapNanos: UInt64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let wasHeld = held
        defer {
            let repeatKey = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let kind = type == .flagsChanged ? "mod" : type == .keyDown ? (repeatKey ? "repeat" : "down") : "up"
            if !repeatKey {
                onEvent?(KeyEventRecord(kind: kind, keyCode: keyCode, key: HotkeyBinding.keyName(keyCode),
                                        modifiers: HotkeyBinding.modifierString(flags), matched: wasHeld != held))
            }
        }
        if let recorder { return handleRecording(type, keyCode: keyCode, flags: flags, event: event, recorder) }

        // CGEvent timestamps are nanoseconds of uptime; reject anything implausible.
        let lag = tapNanos >= event.timestamp ? Double(tapNanos - event.timestamp) / 1e6 : -1
        func fire(_ down: Bool) {
            held = down
            handler?(KeyEdge(down: down, tapHost: tapHost, eventToTapMS: (0..<1000).contains(lag) ? lag : nil))
        }
        if type == .keyDown && keyCode == Int64(kVK_Escape) && flags & HotkeyBinding.relevantModifiers == 0,
           onEscape?() == true { swallowEscapeUp = true; return true }
        if type == .keyUp && keyCode == Int64(kVK_Escape) && swallowEscapeUp { swallowEscapeUp = false; return true }
        if binding.isModifier {
            guard type == .flagsChanged, keyCode == binding.keyCode, let bit = HotkeyBinding.modifierMasks[keyCode] else { return false }
            let down = flags & bit != 0
            if down != held { fire(down) }
            return false   // never swallow modifiers: other apps must see them change
        }
        guard keyCode == binding.keyCode else { return false }
        switch type {
        case .keyDown:
            if held { return true }   // auto-repeat while held
            guard flags & HotkeyBinding.relevantModifiers == binding.modifiers else { return false }
            fire(true); return true
        case .keyUp:
            guard held else { return false }
            fire(false); return true
        default: return false
        }
    }

    private func handleRecording(_ type: CGEventType, keyCode: Int64, flags: UInt64, event: CGEvent,
                                 _ recorder: (HotkeyBinding?) -> Void) -> Bool {
        func finish(_ binding: HotkeyBinding?) {
            if let binding { self.binding = binding; binding.save() }
            self.recorder = nil; candidateModifier = nil
            recorder(binding)
        }
        switch type {
        case .flagsChanged:
            guard let bit = HotkeyBinding.modifierMasks[keyCode] else { return false }
            if flags & bit != 0 { if candidateModifier == nil { candidateModifier = keyCode } }
            else if candidateModifier == keyCode {
                // Pressed and released with no other key: a lone-modifier hotkey.
                finish(HotkeyBinding(keyCode: keyCode, modifiers: 0, isModifier: true))
            }
            return false
        case .keyDown:
            if keyCode == Int64(kVK_Escape) && flags & HotkeyBinding.relevantModifiers == 0 { finish(nil); return true }
            finish(HotkeyBinding(keyCode: keyCode, modifiers: flags & HotkeyBinding.relevantModifiers, isModifier: false))
            return true
        case .keyUp: return true
        default: return false
        }
    }
}
