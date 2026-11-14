@preconcurrency import ApplicationServices
import AppKit
@MainActor struct Focus {
    let element: AXUIElement
    let pid: pid_t
    static func current() -> Focus? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return Focus(element: unsafeBitCast(value, to: AXUIElement.self), pid: app.processIdentifier)
    }
    var stillFocused: Bool { guard let now = Self.current() else { return false }; return pid == now.pid && CFEqual(element, now.element) }
}
