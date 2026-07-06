import AppKit
import SwiftUI
import AVFoundation
import Network

/// Live microphone level (0…1), published on the main thread, that drives the recording
/// waveform. `AudioRecorder` pushes RMS-based values from the audio tap; the overlay
/// observes it. Attack is fast / release is slower so the meter feels lively but smooth.
final class MicLevel: ObservableObject {
    static let shared = MicLevel()
    private init() { startNetworkMonitor() }

    @Published var level: CGFloat = 0
    /// True while we're waiting on a result (transcription/translation) — the overlay then
    /// shows a loader in place of the record dot.
    @Published var processing = false
    /// User setting: show the record dot. The loader is unaffected by this.
    @Published var showDot = true
    /// True when there's no internet connection — the record dot turns red instead of green.
    @Published var isOffline = false

    private let networkMonitor = NWPathMonitor()

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.isOffline = path.status != .satisfied }
        }
        networkMonitor.start(queue: DispatchQueue(label: "BabelBar.NWPathMonitor"))
    }

    func push(_ raw: Float) {
        let v = CGFloat(min(1, max(0, raw)))
        DispatchQueue.main.async {
            if v > self.level { self.level = self.level * 0.4 + v * 0.6 }   // fast attack
            else              { self.level = self.level * 0.82 + v * 0.18 } // slow release
        }
    }

    func reset() { DispatchQueue.main.async { self.level = 0 } }
}

/// Recording pill near the notch/menu-bar brow during voice dictation (even when the app is
/// hidden). FreeFlow-style: the panel extends up to the very top of the screen, filling the
/// notch area with solid black so it merges seamlessly with the notch — only the rounded
/// bottom part protrudes below the brow.
final class RecordingOverlay {
    static let shared = RecordingOverlay()
    private init() {}

    private var panel: NSPanel?
    private let fallbackWidth: CGFloat = 184  // non-notch displays
    private let dropHeight: CGFloat = 22      // visible part below the brow
    private let bottomGap: CGFloat = 4        // gap between the waveform and the pill's bottom

    private var processingDelay: DispatchWorkItem?       // pending "show loader" work
    private let processingShowDelay: TimeInterval = 0.8  // only show the loader if waiting > this

    /// Switch the left indicator between the record dot and a loader. Turning it ON is delayed
    /// by `processingShowDelay` so quick results never flash a spinner; turning it OFF is immediate
    /// and cancels any pending show.
    func setProcessing(_ on: Bool) {
        DispatchQueue.main.async {
            self.processingDelay?.cancel()
            self.processingDelay = nil
            if on {
                let work = DispatchWorkItem { MicLevel.shared.processing = true }
                self.processingDelay = work
                DispatchQueue.main.asyncAfter(deadline: .now() + self.processingShowDelay, execute: work)
            } else {
                MicLevel.shared.processing = false
            }
        }
    }

    func show() {
        processingDelay?.cancel(); processingDelay = nil
        MicLevel.shared.processing = false        // fresh recording → red dot, not loader
        let screen = currentScreen()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let frame = targetFrame(on: screen)
        // Hidden = pulled up so nothing protrudes below the brow; then slides down.
        let hidden = NSRect(x: frame.minX, y: browY(screen), width: frame.width, height: frame.height)
        panel.setFrame(hidden, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.64, 1.0)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide() {
        processingDelay?.cancel(); processingDelay = nil
        MicLevel.shared.reset()
        MicLevel.shared.processing = false
        guard let panel else { return }
        let screen = panel.screen ?? currentScreen()
        var hidden = panel.frame
        hidden.origin.y = browY(screen)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hidden, display: true)
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Bottom edge of the menu bar / notch "brow".
    private func browY(_ screen: NSScreen) -> CGFloat { screen.visibleFrame.maxY }

    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first!
    }

    /// Width + center-x: match the notch exactly on notched displays so the black merges with it.
    private func metrics(for screen: NSScreen) -> (width: CGFloat, midX: CGFloat) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let w = (screen.frame.width - left.width - right.width).rounded()
            let mid = (screen.frame.minX + left.width + w / 2).rounded()
            return (w, mid)
        }
        return (fallbackWidth, screen.frame.midX.rounded())
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let m = metrics(for: screen)
        let menuH = screen.frame.maxY - browY(screen)      // notch / menu-bar height
        let height = (menuH + dropHeight)
        // Top reaches the screen top (fills the notch); bottom protrudes `dropHeight` below brow.
        return NSRect(x: (m.midX - m.width / 2).rounded(),
                      y: (browY(screen) - dropHeight).rounded(),
                      width: m.width, height: height.rounded())
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: fallbackWidth, height: 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false                 // no shadow → seamless merge with the notch
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        let content = VStack(spacing: 0) {
            Spacer(minLength: 0)                            // fills the notch area above
            WaveformOverlayView().frame(height: dropHeight - bottomGap)
            Color.clear.frame(height: bottomGap)            // gap from the bottom edge
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)                            // opaque → merges with the notch
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 13, bottomTrailingRadius: 13,
                                          style: .continuous))
        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        return p
    }
}

/// Voice-reactive waveform: faint dots at the edges that swell into a tight cluster of tall
/// bars in the center, coloured blue → bright lilac → red, plus a decorative red "recording"
/// dot on the left. Bar heights follow the live mic level (`MicLevel`) with a time shimmer.
private struct WaveformOverlayView: View {
    @ObservedObject private var mic = MicLevel.shared

    private let bars = 25
    private let barWidth: CGFloat = 2.0
    private let maxBarHeight: CGFloat = 17      // uses the full pill height (drop 22 − gap 4 ≈ 18pt)
    private let dotMin: CGFloat = 2.0          // edge bars collapse to round dots
    private let stripInset: CGFloat = 38       // horizontal margins → centered, untouched strip

    var body: some View {
        // ~24fps: smooth for this tiny strip while keeping the main thread free (a heavy
        // per-frame redraw here used to stall the run loop and let global Fn leak out).
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Waveform stays centered (symmetric insets) — independent of the indicator.
                waveform(t)
                    .padding(.horizontal, stripInset)

                // Indicator (dot / loader) anchored in the left corner, vertically centered.
                HStack {
                    leftIndicator(t)
                        .frame(width: 17, height: 17)
                    Spacer()
                }
                .padding(.leading, 6)
            }
        }
    }

    private func waveform(_ t: TimeInterval) -> some View {
        Canvas { ctx, size in
            for i in 0..<bars {
                let frac = bars > 1 ? Double(i) / Double(bars - 1) : 0.5
                let x = CGFloat(frac) * size.width
                let h = barHeight(i, t)
                let rect = CGRect(x: x - barWidth / 2,
                                  y: (size.height - h) / 2,
                                  width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                         with: .color(color(at: frac)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func leftIndicator(_ t: TimeInterval) -> some View {
        if mic.processing {
            loader(t)                 // loader always shows when waiting, regardless of the setting
        } else if mic.showDot {
            recordDot                 // red dot only while recording AND the setting is on
        }
    }

    /// Record dot: a soft semi-transparent halo with a crisp SOLID (flat) core inside.
    /// Green while online, red when there's no internet connection.
    private var recordDot: some View {
        let haloColor = mic.isOffline
            ? Color(red: 0.90, green: 0.18, blue: 0.33)   // red
            : Color(red: 0.20, green: 0.85, blue: 0.45)   // green
        let coreColor = mic.isOffline
            ? Color(red: 0.96, green: 0.42, blue: 0.54)   // red
            : Color(red: 0.48, green: 0.95, blue: 0.66)   // green
        return ZStack {
            Circle()
                .fill(haloColor.opacity(0.30))   // translucent halo
                .frame(width: 14, height: 14)
            Circle()
                .fill(coreColor)                 // solid, crisp core
                .frame(width: 8, height: 8)
        }
    }

    /// Small spinner shown during any waiting/processing. Driven by the timeline clock so it
    /// stays smooth without a separate animation that could fight the TimelineView.
    private func loader(_ t: TimeInterval) -> some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(Color.white.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees((t * 540).truncatingRemainder(dividingBy: 360)))
    }

    /// Tall in a tight center cluster, fading to faint dots at the edges; height tracks the
    /// mic level. A steep envelope keeps the excitement near the middle (not the whole width).
    private func barHeight(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let center = Double(bars - 1) / 2
        let dist = abs(Double(i) - center) / center          // 0 center … 1 edge
        let envelope = pow(max(0, 1 - dist), 2.8)            // steep → only the center swells
        let wobble = 0.7 + 0.3 * (0.5 + 0.5 * sin(t * 8 + Double(i) * 0.7))
        let lvl = Double(mic.level)
        let drive = lvl * (1 + 0.5 * envelope)               // center reacts most
        // Tiny idle shimmer (0.06) so it's alive when quiet; voice drives the rest.
        let dynamic = min(1, envelope * (0.06 + 1.0 * drive) * wobble)
        return dotMin + CGFloat(dynamic) * (maxBarHeight - dotMin)
    }

    /// Blue → bright lilac (center, most active) → red; edges dimmed so far dots read faint.
    private func color(at frac: Double) -> Color {
        let blue  = (0.40, 0.46, 0.96)
        let lilac = (0.72, 0.45, 1.0)                        // bright сиреневый peak
        let red   = (1.0, 0.22, 0.36)
        let rgb: (Double, Double, Double)
        if frac < 0.5 {
            let f = frac / 0.5
            rgb = (lerp(blue.0, lilac.0, f), lerp(blue.1, lilac.1, f), lerp(blue.2, lilac.2, f))
        } else {
            let f = (frac - 0.5) / 0.5
            rgb = (lerp(lilac.0, red.0, f), lerp(lilac.1, red.1, f), lerp(lilac.2, red.2, f))
        }
        let edge = abs(frac - 0.5) * 2                       // 0 center … 1 edge
        let alpha = 0.4 + 0.6 * (1 - edge)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2).opacity(alpha)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
