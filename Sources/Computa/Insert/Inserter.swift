import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Inserts text at the user's cursor by pasting: save the clipboard, put the text on it,
/// send ⌘V to the frontmost app, then restore the clipboard.
///
/// Setting kAXSelectedTextAttribute is not used: Chrome, Electron apps and terminals report
/// success without inserting anything. Pasting works wherever ⌘V does.
@MainActor enum Inserter {
    static func insert(_ raw: String, into _: Focus?) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "No speech detected" }
        let pasteboard = NSPasteboard.general
        if IsSecureEventInputEnabled() {
            // A password field (or app holding secure input) won't accept synthetic keys.
            pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
            return "Copied — press ⌘V to insert (secure input is on)"
        }
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount
        postCommandV()
        // Apps read the pasteboard asynchronously after ⌘V (Electron especially), so restore later,
        // and only if nothing else has written to the clipboard in the meantime.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard pasteboard.changeCount == ours else { return }
            restore(saved, to: pasteboard)
        }
        return "Inserted"
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        // Neutralise any modifiers still physically held (e.g. ⌃⇧ from the hotkey) so the app sees plain ⌘V.
        for (key, down) in [(CGKeyCode(kVK_ANSI_V), true), (CGKeyCode(kVK_ANSI_V), false)] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
    }
    private static func restore(_ items: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        })
    }
}
