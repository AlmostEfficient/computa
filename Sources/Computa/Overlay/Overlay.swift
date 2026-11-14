import AppKit
import SwiftUI

/// Floating dictation pill. Appears instantly (no entrance animation), leaves with a ~120 ms fade.
/// Never takes focus: the user's text field stays key while they talk.
@MainActor @Observable final class OverlayModel {
    enum Phase { case listening, transcribing }
    var phase = Phase.listening
    /// Newest level first; drawn as a ripple from the centre bar outwards.
    var history = [Float](repeating: 0, count: 5)
    var onCancel: () -> Void = {}
    private var smoothed: Float = 0
    func push(_ level: Float) {
        // Fast attack, slow release, so speech reads as movement rather than flicker.
        smoothed = level > smoothed ? level : smoothed * 0.82 + level * 0.18
        history.removeLast(); history.insert(smoothed, at: 0)
    }
    func reset() { history = Array(repeating: 0, count: history.count); smoothed = 0; phase = .listening }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class OverlayController {
    let model = OverlayModel()
    private let panel: OverlayPanel
    private static let size = NSSize(width: 196, height: 44)
    private var hiding = false

    init() {
        panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    func show() {
        hiding = false
        model.reset()
        // Bottom centre of the screen the pointer is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: (area.midX - Self.size.width / 2).rounded(), y: area.minY + 28))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hiding else { return }   // a new show() during the fade wins
                self.panel.orderOut(nil); self.hiding = false
            }
        })
    }
}

private enum Palette {
    static let fill = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let stroke = Color.white.opacity(0.09)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.80)
    static let barIdle = Color.white.opacity(0.18)
    static let barLive = Color.white.opacity(0.55)
}

private struct OverlayView: View {
    let model: OverlayModel
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: model.phase == .listening ? "ear" : "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            Spacer(minLength: 0)
            Meter(history: model.history, active: model.phase == .listening)
            Spacer(minLength: 0)
            CancelButton(action: model.onCancel)
        }
        .padding(.horizontal, 8)
        .frame(width: 196, height: 44)
        .background(Capsule().fill(Palette.fill))
        .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
        .transaction { $0.animation = nil }   // state changes snap; only the window fade animates
    }
}

private struct Meter: View {
    let history: [Float]
    let active: Bool
    private let shape: [Float] = [0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.45, 0.4]
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<9, id: \.self) { i in
                // Centre bar = newest level; neighbours carry older ones outwards.
                let age = min(abs(i - 4), history.count - 1)
                let level = active ? history[age] * shape[i] : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(level > 0.08 ? Palette.barLive : Palette.barIdle)
                    .frame(width: 5, height: CGFloat(5 + level * 15))
            }
        }
        .frame(height: 20)
    }
}

private struct CancelButton: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.accent.opacity(hover ? 0.28 : 0.14))
                Circle().strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1.5)
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Cancel dictation")
    }
}
