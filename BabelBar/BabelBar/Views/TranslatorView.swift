import SwiftUI
import AppKit

struct TranslatorView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var theme: AppTheme   // observe theme so text/colors recolor live
    @State private var lastInput: String = ""
    @State private var hoverDirection = false

    /// Fraction of the available height given to the TOP (input) text area. The draggable
    /// handle between the two areas adjusts it; clamped so neither area collapses.
    @State private var splitRatio: CGFloat = 0.5
    @State private var dragStartRatio: CGFloat? = nil

    var body: some View {
        VStack(spacing: 8) {
            topBar
            splitTextAreas
            bottomBar
        }
        .background(
            ZStack {
                // Hidden ⌘↵ shortcut to trigger translation.
                Button("") { state.translate() }
                    .keyboardShortcut(.return, modifiers: .command)
                // Escape hides the window.
                Button("") { state.onRequestClose?() }
                    .keyboardShortcut(.cancelAction)
            }
            .opacity(0)
        )
        .onAppear { lastInput = state.inputText }
        .onChange(of: state.inputText) { newValue in
            handleInputChange(old: lastInput, new: newValue)
            lastInput = state.inputText
        }
    }

    private func handleInputChange(old: String, new: String) {
        // Auto-translate on paste (multi-character insert/replacement). Plain Enter is handled
        // by PlainTextView.onSubmit; Shift/Option+Enter inserts a newline.
        if abs(new.count - old.count) > 1, !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.translate()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("BabelBar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            // Direction switcher — sits right next to the title.
            Button {
                state.swapDirection()
            } label: {
                HStack(spacing: 5) {
                    Text(state.sourceLang.code)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(state.targetLang.code)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hoverDirection ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(hoverDirection ? 0.10 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverDirection = $0 }

            Spacer()

            HoverTextButton(title: state.t(.clear)) { state.clear() }
                .layoutPriority(1)

            IconButton(systemName: "pin.fill", active: state.isPinned) {
                state.isPinned.toggle()
            }
            IconButton(systemName: "gearshape") {
                state.onOpenSettings?()
            }
            IconButton(systemName: "xmark") {
                state.onRequestClose?()
            }
        }
    }

    // MARK: - Split text areas (input / handle / output)

    private var splitTextAreas: some View {
        GeometryReader { geo in
            let handleH: CGFloat = 16
            let minBlock: CGFloat = 96
            let avail = max(geo.size.height - handleH, minBlock * 2)
            let topH = min(max(avail * splitRatio, minBlock), avail - minBlock)

            VStack(spacing: 0) {
                inputBlock
                    .frame(height: topH)

                ResizeHandle()
                    .frame(height: handleH)
                    .background(_HandleDragBlocker())   // claim the drag (don't move the window)
                    .gesture(
                        // Global coordinate space: the handle moves as the split changes, so a
                        // local-space translation would feed back on itself and jitter. Global
                        // space is fixed → smooth, 1:1 height adjustment.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartRatio ?? splitRatio
                                if dragStartRatio == nil { dragStartRatio = start }
                                let r = start + value.translation.height / avail
                                splitRatio = min(max(r, minBlock / avail), (avail - minBlock) / avail)
                            }
                            .onEnded { _ in dragStartRatio = nil }
                    )

                outputBlock
                    .frame(height: avail - topH)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var inputBlock: some View {
        textBlock(
            text: $state.inputText,
            placeholder: state.isDictating ? state.t(.dictatingPlaceholder) : state.t(.inputPlaceholder),
            editable: true,
            showsMic: true,
            onSubmit: { state.translate() }
        )
    }

    private var outputBlock: some View {
        textBlock(
            text: $state.outputText,
            placeholder: state.isTranslating ? state.t(.translatingPlaceholder) : state.t(.outputPlaceholder),
            editable: true,
            showsSpinner: true,
            onSubmit: { state.translate(reverse: true) }   // edit → translate back to top
        )
    }

    // MARK: - Text block

    private func textBlock(text: Binding<String>, placeholder: String, editable: Bool,
                           showsSpinner: Bool = false, showsMic: Bool = false,
                           onSubmit: @escaping () -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundColor(Theme.textPlaceholder)
                    .font(.system(size: Theme.translationFontSize))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }

            PlainTextView(text: text, isEditable: editable, fontSize: Theme.translationFontSize,
                          textColor: Theme.textPrimary, onSubmit: editable ? onSubmit : nil)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 32)

            // Bottom-right: counter + copy
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    if showsMic {
                        Button { state.toggleDictation() } label: {
                            Image(systemName: state.isDictating ? "mic.fill" : "mic")
                                .font(.system(size: 14))
                                .foregroundColor(state.isDictating ? .red : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(state.t(.voiceInputTip))
                    }
                    Spacer()
                    Text("\(text.wrappedValue.count)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                    HoverIconButton(systemName: "doc.on.doc", size: 12) {
                        ClipboardHelper.copy(text.wrappedValue)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)   // equal gap to the right edge and the bottom edge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(corner: 16)
        .overlay(alignment: .center) {
            if showsSpinner && state.isTranslating {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Insert-translation button

    private var insertButton: some View {
        InsertTranslationButton(title: state.t(.insertTranslation)) { state.insertTranslation() }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        // ZStack so the insert button is centered on the WINDOW, independent of the side
        // content widths (otherwise it drifts toward whichever side has less content).
        ZStack {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Text("⌘").font(.system(size: 10, weight: .semibold))
                    Text("+ C + C").font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Theme.accentPurple)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.accentPurple.opacity(0.15))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.accentPurple.opacity(0.4), lineWidth: 1)
                )
                .hoverTip(state.t(.forQuickCopy))   // label moved into a hover tooltip

                Spacer()

                if let err = state.errorMessage {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(state.apiStatus.color)
                        .frame(width: 6, height: 6)
                    // Active provider abbreviation (e.g. "OpenAI" / "DeepSeek") when online,
                    // otherwise the status label.
                    Text(state.apiStatus == .online ? state.activeProviderName : state.apiStatusLabel())
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textPrimary)
                }
            }

            if state.canInsertTranslation {
                insertButton   // dead-center of the window
            }
        }
    }
}

/// Draggable divider between the two text areas. A small pill that widens on hover (with a
/// resize cursor); dragging it up/down reassigns height between the input and output areas.
private struct ResizeHandle: View {
    @State private var hover = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Theme.textPrimary.opacity(hover ? 0.28 : 0.14))
                .frame(width: hover ? 58 : 40, height: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { h in
            hover = h
            if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .animation(.easeInOut(duration: 0.28), value: hover)
    }
}

/// Tells macOS this view's area is not a window-drag region, so the resize handle's own
/// drag gesture works instead of moving the whole (movable-by-background) window.
private struct _HandleDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BlockerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
