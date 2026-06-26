import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var theme: AppTheme

    var body: some View {
        ZStack {
            // Themed background fills the window (the host NSVisualEffectView clips it to the
            // rounded corners). Opacity is user-configurable (Background Opacity slider).
            Theme.windowBackground.opacity(Theme.backgroundOpacity)

            TranslatorView()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)        // tight, symmetric gap under the insert button
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 388, maxHeight: .infinity)
        .tooltipLayer()
        // Bottom-right resize affordance — drag it to grow/shrink the window.
        .overlay(alignment: .bottomTrailing) {
            WindowResizeGrip()
                .frame(width: 16, height: 16)
                .padding(5)
        }
        // Propagate the theme revision so glass panels recolor live without rebuilding.
        .environment(\.themeRevision, theme.revision)
        .preferredColorScheme(colorScheme)
        .onAppear { theme.installFor(appearance: state.settings.appearance) }
        .onChange(of: state.settings.appearance) { _ in theme.installFor(appearance: state.settings.appearance) }
    }

    private var colorScheme: ColorScheme? {
        switch state.settings.appearance {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

/// A diagonal grip in the window's bottom-right corner that resizes the window when dragged
/// (the window is borderless, so it has no native resize affordance to discover). Keeps the
/// top-left corner anchored and grows toward the bottom-right; respects the window's minSize.
struct WindowResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ nsView: GripView, context: Context) {}

    final class GripView: NSView {
        private var startMouse: NSPoint = .zero
        private var startFrame: NSRect = .zero
        private var hover = false
        private var tracking: NSTrackingArea?

        override var isFlipped: Bool { true }                 // top-left origin, like SwiftUI
        override var mouseDownCanMoveWindow: Bool { false }   // we handle the drag, not the window
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let t = tracking { removeTrackingArea(t) }
            let t = NSTrackingArea(rect: bounds,
                                   options: [.mouseEnteredAndExited, .activeAlways],
                                   owner: self, userInfo: nil)
            addTrackingArea(t); tracking = t
        }

        override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent)  { hover = false; needsDisplay = true }

        override func mouseDown(with event: NSEvent) {
            guard let w = window else { return }
            startMouse = NSEvent.mouseLocation
            startFrame = w.frame
        }

        override func mouseDragged(with event: NSEvent) {
            guard let w = window else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - startMouse.x
            let dy = now.y - startMouse.y                     // screen coords: y grows upward
            let newW = max(w.minSize.width,  startFrame.width  + dx)
            let newH = max(w.minSize.height, startFrame.height - dy)
            // Anchor the top-left: keep origin.x and the top edge (maxY) fixed.
            let frame = NSRect(x: startFrame.origin.x,
                               y: startFrame.maxY - newH,
                               width: newW, height: newH)
            w.setFrame(frame, display: true)
        }

        override func draw(_ dirtyRect: NSRect) {
            let color = NSColor.white.withAlphaComponent(hover ? 0.6 : 0.32)
            color.setStroke()
            let p = NSBezierPath()
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            let w = bounds.width, h = bounds.height
            p.move(to: NSPoint(x: w, y: h * 0.30)); p.line(to: NSPoint(x: w * 0.30, y: h))
            p.move(to: NSPoint(x: w, y: h * 0.64)); p.line(to: NSPoint(x: w * 0.64, y: h))
            p.stroke()
        }
    }
}
