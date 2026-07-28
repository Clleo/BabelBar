import SwiftUI
import AppKit

/// Live app palette. Values are mutable so the ThemeKit module can re-skin the app
/// at runtime; views re-read them whenever the observed AppTheme publishes a change.
enum Theme {
    static var bgTop = Color(red: 0.105, green: 0.105, blue: 0.110)
    static var bgBottom = Color(red: 0.060, green: 0.060, blue: 0.065)
    static var panel = Theme.textPrimary.opacity(0.045)
    /// Fill for inputs / text areas — a touch more contrasty than `panel` so they don't merge
    /// with the section card they sit in. Set by ThemeKit (surface blended toward foreground).
    static var fieldFill = Theme.textPrimary.opacity(0.10)
    static var panelStroke = Theme.textPrimary.opacity(0.08)
    static var textPrimary = Color.white
    static var textSecondary = Theme.textPrimary.opacity(0.78)
    static var textPlaceholder = Theme.textPrimary.opacity(0.42)
    static let accentGreen = Color(red: 0.30, green: 0.85, blue: 0.46) // status color, fixed
    static var accentBlue = Color(red: 0.36, green: 0.45, blue: 0.95)
    static var accentPurple = Color(red: 0.60, green: 0.38, blue: 0.95)

    /// Font size for the translator's input/output text areas.
    static var translationFontSize: CGFloat = 14

    /// Unified sizing/border for all capsule controls (recorders, pickers, segments, pills, fields)
    /// so they line up at the same height with the same outline.
    static let controlHeight: CGFloat = 28
    static var controlBorder: Color { Theme.textPrimary.opacity(0.12) }

    /// Opacity of the window background fill (0…1). Lower = more blur shows through.
    static var backgroundOpacity: Double = 0.97

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentBlue, accentPurple], startPoint: .leading, endPoint: .trailing)
    }

    static var windowBackground: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Environment value bumped on every theme change, so view modifiers that read the static
/// `Theme.*` palette (which isn't itself observable) re-evaluate and recolor live.
private struct ThemeRevisionKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var themeRevision: Int {
        get { self[ThemeRevisionKey.self] }
        set { self[ThemeRevisionKey.self] = newValue }
    }
}

/// Reusable rounded glass panel.
struct GlassPanel: ViewModifier {
    var corner: CGFloat = 16
    @Environment(\.themeRevision) private var revision   // forces re-eval on theme change

    func body(content: Content) -> some View {
        _ = revision
        return content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(corner: CGFloat = 16) -> some View {
        modifier(GlassPanel(corner: corner))
    }
}

/// Like `glassPanel`, but a touch more contrasty than a section card so inputs / text areas
/// don't visually merge with the panel they sit in. Tints toward the text color: lighter in
/// dark themes, slightly darker in light themes — readable separation either way.
struct FieldPanel: ViewModifier {
    var corner: CGFloat = 9
    @Environment(\.themeRevision) private var revision

    func body(content: Content) -> some View {
        _ = revision
        return content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
    }
}

extension View {
    func fieldPanel(corner: CGFloat = 9) -> some View {
        modifier(FieldPanel(corner: corner))
    }
}

/// NSVisualEffectView wrapper — translucent blurred background with optional rounding.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        v.wantsLayer = true
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = cornerRadius > 0
    }
}

/// Lightweight NSTextView wrapper without scrollbars and without internal padding.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var fontSize: CGFloat = 15
    /// Explicit reactive text color: passing it as an input guarantees SwiftUI re-runs
    /// `updateNSView` when the theme's foreground changes, so the text recolors live.
    var textColor: Color = Theme.textPrimary
    /// Called on plain Enter (submit). Shift+Enter / Option+Enter insert a newline instead.
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        if let tv = scroll.documentView as? NSTextView {
            tv.delegate = context.coordinator
            tv.isEditable = isEditable
            tv.isSelectable = true
            tv.isRichText = false
            tv.allowsUndo = true
            tv.backgroundColor = .clear
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 0, height: 4)
            tv.usesAdaptiveColorMappingForDarkAppearance = false
            tv.insertionPointColor = NSColor(textColor)
            tv.font = NSFont.systemFont(ofSize: fontSize)
            tv.textColor = NSColor(textColor)
            tv.typingAttributes = Self.attributes(fontSize: fontSize, color: textColor)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        let attrs = Self.attributes(fontSize: fontSize, color: textColor)
        tv.insertionPointColor = NSColor(textColor)
        if tv.string != text {
            tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        } else {
            // Re-apply colour/size to existing text (theme may have changed).
            tv.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: tv.string.utf16.count))
        }
        tv.typingAttributes = attrs
        tv.isEditable = isEditable
    }

    /// Extra space between lines in the translation/AI-instructions text areas (was 0).
    static let lineSpacing: CGFloat = 4

    private static func attributes(fontSize: CGFloat, color: Color) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        return [.font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(color),
                .paragraphStyle: para]
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextView
        init(_ p: PlainTextView) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        // Enter = submit; Shift+Enter / Option+Enter = newline (messenger-style).
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(self)   // insert a line break
                return true
            }
            parent.onSubmit?()                                    // translate
            return true                                           // swallow the newline
        }
    }
}

/// Small icon button used in the top bar.
struct IconButton: View {
    let systemName: String
    var active: Bool = false
    let action: () -> Void
    @State private var hover = false

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? Theme.accentPurple : (hover ? Theme.textPrimary : Theme.textSecondary))
                .frame(width: 22, height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(hover ? 0.10 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Tiny icon button (e.g. inline copy) with a subtle hover background.
struct HoverIconButton: View {
    let systemName: String
    var size: CGFloat = 12
    let action: () -> Void
    @State private var hover = false
    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        _ = revision
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundColor(hover ? Theme.textPrimary : Theme.textSecondary)
                .padding(4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(hover ? 0.10 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// "Insert translation »»" pill button shown in the bottom bar.
struct InsertTranslationButton: View {
    var title: String = "Insert translation"
    let action: () -> Void
    @State private var hover = false

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                Text("»»")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accentGradient)   // accent, like the Save button
            }
            .foregroundColor(Theme.textPrimary)
            .frame(width: 180, height: 28)
            .background(
                Capsule(style: .continuous)   // fully rounded (pill)
                    .fill(Theme.textPrimary.opacity(hover ? 0.16 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.textPrimary.opacity(0.14), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Click-to-record keyboard shortcut badge. Click → "press keys" → captures a KeyCombo.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo
    var requireModifier: Bool = true
    var doubleTap: Bool = false
    var recordingPrompt: String = "Press keys…"
    var onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hover = false

    private var label: String {
        if recording { return recordingPrompt }
        return doubleTap ? combo.displayDoubled : combo.display
    }

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        Button {
            recording ? stop() : start()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(recording ? Theme.accentPurple : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(minWidth: 95).frame(height: Theme.controlHeight)   // uniform badge size
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(recording ? 0.14 : (hover ? 0.10 : 0.05)))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(recording ? Theme.accentPurple.opacity(0.6) : Theme.controlBorder,
                                lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels

            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Require at least one modifier (unless it's a function key) to avoid grabbing plain keys.
            if requireModifier && mods.isEmpty && !(event.keyCode >= 96 && event.keyCode <= 122) {
                NSSound.beep(); return nil
            }
            combo = KeyCombo(
                keyCode: UInt32(event.keyCode),
                command: mods.contains(.command),
                shift: mods.contains(.shift),
                option: mods.contains(.option),
                control: mods.contains(.control)
            )
            stop()
            onChange()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - Custom tooltips (dark, blurred, borderless, pointing right)

/// The currently-hovered tooltip, bubbled up to the window root via a preference so the
/// bubble can be drawn on top of everything and never clipped by a scroll view.
struct TooltipData: Equatable {
    let text: String
    let anchor: Anchor<CGRect>
}

struct TooltipKey: PreferenceKey {
    static var defaultValue: TooltipData? = nil
    static func reduce(value: inout TooltipData?, nextValue: () -> TooltipData?) {
        if let n = nextValue() { value = n }
    }
}

/// Marks a view as the source of a tooltip — publishes its bounds + text while hovered.
struct TooltipSource: ViewModifier {
    let text: String
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .anchorPreference(key: TooltipKey.self, value: .bounds) { anchor in
                hover ? TooltipData(text: text, anchor: anchor) : nil
            }
    }
}

extension View {
    /// Attach a hover tooltip to any view (e.g. the ⌘+C+C badge).
    func hoverTip(_ text: String) -> some View { modifier(TooltipSource(text: text)) }

    /// Install once at a window root: renders the hovered tooltip bubble, positioned to the
    /// RIGHT of its source, above all content.
    func tooltipLayer() -> some View {
        overlayPreferenceValue(TooltipKey.self) { data in
            GeometryReader { proxy in
                if let data {
                    let rect = proxy[data.anchor]
                    let total = TooltipBubble.totalWidth
                    TooltipBubble(text: data.text)
                        .fixedSize()
                        .position(x: rect.maxX + 6 + total / 2, y: rect.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The tooltip bubble: one continuous shape (rounded panel + small left arrow) filled with a
/// translucent blurred material and a light tint — so it sits a couple tones above the window
/// background, stays see-through, and the arrow matches the body exactly. No border.
struct TooltipBubble: View {
    let text: String
    static let textWidth: CGFloat = 210
    static let arrowWidth: CGFloat = 6
    static let hPad: CGFloat = 12
    static let totalWidth: CGFloat = arrowWidth + hPad * 2 + textWidth

    var body: some View {
        let shape = TooltipShape(arrow: Self.arrowWidth, radius: 10)
        // Theme-independent: always a dark bubble with light text, so it stays readable in both
        // light and dark themes (a light theme used to give dark text on a dark bubble).
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Color.white.opacity(0.95))
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .frame(width: Self.textWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
            .padding(.leading, Self.arrowWidth + Self.hPad)   // room for the arrow on the left
            .padding(.trailing, Self.hPad)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)            // transparency + blur (cheap)
                    shape.fill(Color.black.opacity(0.55))     // force a dark bubble in any theme
                }
            }
            .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
    }
}

/// Rounded panel with a small left-pointing arrow, as a single path so one fill covers both
/// (the arrow is never a different colour than the body).
private struct TooltipShape: Shape {
    var arrow: CGFloat = 6
    var radius: CGFloat = 10
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX + arrow, y: rect.minY,
                          width: rect.width - arrow, height: rect.height)
        var p = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        let midY = rect.midY
        var tri = Path()
        tri.move(to: CGPoint(x: rect.minX, y: midY))                       // tip, points left
        tri.addLine(to: CGPoint(x: rect.minX + arrow + 1, y: midY - 6))
        tri.addLine(to: CGPoint(x: rect.minX + arrow + 1, y: midY + 6))
        tri.closeSubpath()
        p.addPath(tri)
        return p
    }
}

/// A small "?" help icon that shows a tooltip (to its right) on hover.
struct HelpTip: View {
    let text: String
    @State private var hover = false
    @Environment(\.themeRevision) private var revision   // re-read Theme colors on theme switch

    var body: some View {
        _ = revision
        return Image(systemName: "questionmark.circle")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(hover ? Theme.accentBlue : Theme.textSecondary)
            .onHover { hover = $0 }
            .hoverTip(text)
    }
}

/// Capsule-styled dropdown ("sausage") that replaces the native macOS Picker bezel, so all
/// controls share one rounded look. Built on `Menu` with a borderless style + custom label.
struct CapsulePicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let title: (T) -> String
    var width: CGFloat? = nil
    @State private var hover = false

    @State private var open = false

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Text(title(selection))
                    .font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 13)
            .frame(width: width, height: Theme.controlHeight)
            .background(Capsule().fill(Theme.textPrimary.opacity(hover ? 0.13 : 0.07)))
            .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(options, id: \.self) { opt in
                        CapsuleMenuRow(text: title(opt), selected: opt == selection,
                                       width: max(width ?? 170, 160)) {
                            selection = opt; open = false
                        }
                    }
                }
                .padding(5)
            }
            .frame(maxHeight: 280)
        }
    }
}

/// One row inside CapsulePicker's popover list (hover-highlighted, checkmark on the selected).
private struct CapsuleMenuRow: View {
    let text: String
    let selected: Bool
    let width: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text).font(.system(size: 12)).foregroundColor(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.accentBlue)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.10 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Themed on/off switch — green when on (familiar macOS look), a visible neutral track when
/// off. Replaces the native `Toggle(.switch)` which is nearly invisible on the light surface.
struct CapsuleToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accentGreen : Theme.textPrimary.opacity(0.22))
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.20), radius: 1, y: 0.5)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }
    }
}

/// Capsule-shaped segmented control ("sausage"): a pill track with a pill highlight on the
/// selected segment. Replaces the native `.segmented` Picker so toggles match the other pills.
struct CapsuleSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let title: (T) -> String

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { opt in
                let isSel = opt == selection
                Text(title(opt))
                    .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                    .foregroundColor(isSel ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Capsule().fill(isSel ? Theme.textPrimary.opacity(0.16) : Color.clear).padding(2))
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { selection = opt } }
            }
        }
        .frame(height: Theme.controlHeight)
        .background(Capsule().fill(Theme.textPrimary.opacity(0.05)))
        .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))
    }
}

/// Trailing status pill for a permission row: "Granted ✓" (static) or "Open Settings ⚠︎"
/// (a button that opens System Settings). Mirrors the mockup: text + status glyph in a capsule.
struct PermissionPill: View {
    let granted: Bool
    let grantedText: String
    let actionText: String
    let action: () -> Void
    @State private var hover = false

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        if granted {
            HStack(spacing: 6) {
                Text(grantedText).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textSecondary)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundColor(Theme.accentGreen)
            }
            .padding(.horizontal, 13).frame(height: Theme.controlHeight)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.06)))
            .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(actionText).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textPrimary)
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundColor(.orange)
                }
                .padding(.horizontal, 13).frame(height: Theme.controlHeight)
                .background(Capsule().fill(Theme.textPrimary.opacity(hover ? 0.14 : 0.08)))
                .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

// MARK: - GlowOrbSlider

/// NSView background that tells macOS "this area belongs to our gesture, not the window drag".
/// Without this the window moves instead of the slider thumb on borderless windows.
private struct _SliderGestureBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> _BlockerView { _BlockerView() }
    func updateNSView(_ v: _BlockerView, context: Context) {}

    final class _BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// Thin-track slider with a solid purple orb thumb and a soft blurred border ring.
/// Replaces the system Slider everywhere in the UI for a consistent look.
struct GlowOrbSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    /// Called with `true` when drag begins, `false` when it ends (mirrors Slider.onEditingChanged).
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @Environment(\.isEnabled) private var isEnabled

    private let trackHeight: CGFloat = 3
    private let thumbD: CGFloat = 15        // solid circle diameter
    private let hitH:   CGFloat = 22        // total height — matches a color-swatch row

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func fractionToValue(_ f: Double) -> Double {
        var v = f * (range.upperBound - range.lowerBound) + range.lowerBound
        if step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        GeometryReader { geo in
            let available = max(geo.size.width - thumbD, 1)
            let thumbX   = fraction * available + thumbD / 2

            ZStack(alignment: .leading) {

                // ── Track ──────────────────────────────────────────
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.textPrimary.opacity(isEnabled ? 0.13 : 0.05))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbD / 2)

                // ── Thumb ──────────────────────────────────────────
                ZStack {
                    // Glassmorphism disc behind the orb — frosted translucent ring,
                    // no glow, no border.
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().fill(Color(red: 0.58, green: 0.47, blue: 1.00)
                                .opacity(isEnabled ? 0.16 : 0.04))
                        )
                        .frame(width: thumbD + 6, height: thumbD + 6)
                        .opacity(isEnabled ? 1.0 : 0.5)

                    // Solid orb
                    Circle()
                        .fill(Color(red: 0.55, green: 0.44, blue: 0.96)
                            .opacity(isEnabled ? 1.0 : 0.28))
                        .frame(width: thumbD, height: thumbD)
                        .scaleEffect(isDragging ? 1.08 : 1.0)
                        .animation(.easeOut(duration: 0.10), value: isDragging)
                }
                .position(x: thumbX, y: geo.size.height / 2)
            }
            // Block macOS window-drag from stealing our mouse events
            .background(_SliderGestureBlocker())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let f = min(max((drag.location.x - thumbD / 2) / available, 0), 1)
                        value = fractionToValue(f)
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: hitH)
    }
}

/// Plain text button with a subtle hover background.
struct HoverTextButton: View {
    let title: String
    var fontSize: CGFloat = 11
    let action: () -> Void
    @State private var hover = false

    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize))
                .foregroundColor(hover ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(hover ? 0.10 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
