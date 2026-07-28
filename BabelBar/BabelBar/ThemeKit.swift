import SwiftUI
import AppKit

// =============================================================================
//  ThemeKit — a drop-in, reusable app-theming module.
//
//  To reuse in another product:
//    1. Drop this file in.
//    2. Add a `Theme` enum exposing the mutable palette vars (see BabelBar's
//       Theme.swift) and a `Theme.apply(...)` bridge, OR adapt `AppTheme.reapply`.
//    3. Create one `AppTheme()` in your app state, inject it as an
//       @EnvironmentObject, call `theme.install(isDark:)` once at launch.
//    4. Drop `ThemeEditorView(theme:)` anywhere in your settings UI.
// =============================================================================

// MARK: - Model

/// A full per-mode theme variant: colors plus its own contrast / opacity / blur, so dark and
/// light each remember their own slider positions independently.
struct Palette: Codable, Equatable {
    var accent: String
    var background: String      // window background
    var foreground: String      // text
    var surface: String         // inner panels & text fields
    var contrast: Double = 50          // 0…100, 50 = neutral
    var backgroundOpacity: Double = 90 // 0…100, lower = more glass
    var blur: Double = 60              // 0…100, density of the blur material

    init(accent: String, background: String, foreground: String, surface: String,
         contrast: Double = 50, backgroundOpacity: Double = 90, blur: Double = 60) {
        self.accent = accent; self.background = background
        self.foreground = foreground; self.surface = surface
        self.contrast = contrast; self.backgroundOpacity = backgroundOpacity; self.blur = blur
    }

    enum CodingKeys: String, CodingKey {
        case accent, background, foreground, surface, contrast, backgroundOpacity, blur
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = (try? c.decode(String.self, forKey: .accent)) ?? "#5C73F2"
        background = (try? c.decode(String.self, forKey: .background)) ?? "#16171D"
        foreground = (try? c.decode(String.self, forKey: .foreground)) ?? "#FFFFFF"
        surface = (try? c.decode(String.self, forKey: .surface)) ?? "#23252E"
        contrast = (try? c.decode(Double.self, forKey: .contrast)) ?? 50
        backgroundOpacity = (try? c.decode(Double.self, forKey: .backgroundOpacity)) ?? 90
        blur = (try? c.decode(Double.self, forKey: .blur)) ?? 60
    }
}

/// Persisted theme configuration: separate palettes for dark/light + shared
/// text size and a global contrast knob.
struct ThemeConfig: Codable, Equatable {
    var dark = Palette(accent: "#5C73F2", background: "#16171D", foreground: "#FFFFFF", surface: "#23252E")
    var light = Palette(accent: "#3467AB", background: "#EEF0F5", foreground: "#1C1E27", surface: "#FFFFFF")
    var translationTextSize: Double = 14   // shared (not theme-dependent)

    enum CodingKeys: String, CodingKey { case dark, light, translationTextSize }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dark = (try? c.decode(Palette.self, forKey: .dark)) ?? ThemeConfig().dark
        light = (try? c.decode(Palette.self, forKey: .light)) ?? ThemeConfig().light
        translationTextSize = (try? c.decode(Double.self, forKey: .translationTextSize)) ?? 14
    }
}

// MARK: - Persistence

enum ThemeStore {
    private static let key = "babelbar.theme"

    static func load() -> ThemeConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(ThemeConfig.self, from: data) else {
            return ThemeConfig()
        }
        return cfg
    }

    static func save(_ cfg: ThemeConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Live theme controller

/// Holds the editable config and pushes resolved colors into the global `Theme`.
final class AppTheme: ObservableObject {
    @Published var config: ThemeConfig {
        didSet {
            ThemeStore.save(config)
            reapply()
            revision &+= 1   // force dependent views to rebuild and re-read Theme.*
        }
    }
    /// Bumped on every change so views can `.id(theme.revision)` for guaranteed live recolor.
    @Published var revision: Int = 0

    /// Current resolved appearance; AppDelegate uses it to match window/blur material.
    private(set) var currentIsDark = true
    /// Called on any theme change so the AppKit window chrome (appearance + blur material) updates.
    var onChromeChanged: (() -> Void)?

    init() {
        config = ThemeStore.load()
    }

    /// The palette for the currently visible appearance.
    var activePalette: Palette { currentIsDark ? config.dark : config.light }

    /// Blur intensity (0…1) from the active palette's blur slider. Drives the blur view's
    /// alpha — a single continuous value, so the blur fades smoothly (no material "jumps") and
    /// at 0 the frosting disappears entirely, revealing the clear desktop.
    var blurAlpha: CGFloat { CGFloat(max(0, min(1, activePalette.blur / 100.0))) }

    /// Call once at launch and whenever the effective appearance changes.
    func install(isDark: Bool) {
        currentIsDark = isDark
        reapply()
        revision &+= 1
    }

    /// Resolve dark/light from the app Appearance (handling .system) and apply.
    func installFor(appearance: Appearance) {
        let dark: Bool
        switch appearance {
        case .dark:   dark = true
        case .light:  dark = false
        case .system: dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        install(isDark: dark)
    }

    private func reapply() {
        let p = activePalette
        // Contrast: 50 = neutral (factor 1.0); >50 spreads colors apart, <50 flattens them.
        let factor = p.contrast / 50.0
        Theme.backgroundOpacity = max(0, min(1, p.backgroundOpacity / 100.0))
        Theme.apply(
            accent: Color(hex: p.accent),
            background: Color(hex: p.background).contrasted(factor),
            foreground: Color(hex: p.foreground).contrasted(factor),
            surface: Color(hex: p.surface).contrasted(factor),
            translationFontSize: CGFloat(config.translationTextSize)
        )
        onChromeChanged?()
    }
}

// MARK: - Theme bridge

extension Theme {
    /// Re-skins the global palette from resolved colors.
    static func apply(accent: Color, background: Color, foreground: Color, surface: Color, translationFontSize: CGFloat) {
        Theme.accentBlue        = accent
        Theme.accentPurple      = accent.lightened(0.12)
        Theme.bgBottom          = background
        Theme.bgTop             = background.lightened(0.045)
        Theme.textPrimary       = foreground
        Theme.textSecondary     = foreground.opacity(0.78)   // titles/icons/switcher — readable
        Theme.textPlaceholder   = foreground.opacity(0.42)
        Theme.panel             = surface          // section cards show the picked color as-is
        // Inputs/text areas: surface nudged toward the text color so they read as distinct
        // from the card (lighter in dark themes, slightly darker in light themes).
        let surfNS = NSColor(surface), fgNS = NSColor(foreground)
        Theme.fieldFill         = Color(surfNS.blended(withFraction: 0.16, of: fgNS) ?? surfNS)
        Theme.panelStroke       = foreground.opacity(0.12)
        Theme.translationFontSize = translationFontSize
    }
}

// MARK: - Color <-> hex helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: " #")).uppercased()
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        if s.count == 6 {
            self = Color(red: Double((rgb >> 16) & 0xFF) / 255,
                         green: Double((rgb >> 8) & 0xFF) / 255,
                         blue: Double(rgb & 0xFF) / 255)
        } else {
            self = .black
        }
    }

    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }

    func lightened(_ amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func adj(_ c: CGFloat) -> Double { Double(min(1, max(0, c + CGFloat(amount)))) }
        return Color(red: adj(ns.redComponent), green: adj(ns.greenComponent), blue: adj(ns.blueComponent))
    }

    /// Pivots each channel around mid-gray (0.5): factor 1 = unchanged, >1 boosts
    /// contrast (darks darker / lights lighter), <1 flattens toward gray.
    func contrasted(_ factor: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func adj(_ c: CGFloat) -> Double {
            let v = (Double(c) - 0.5) * factor + 0.5
            return min(1, max(0, v))
        }
        return Color(red: adj(ns.redComponent), green: adj(ns.greenComponent), blue: adj(ns.blueComponent))
    }
}

// MARK: - Editor UI (the reusable module view)

struct ThemeEditorView: View {
    @ObservedObject var theme: AppTheme
    /// The single appearance control (Light / Dark / System). Drives BOTH the live
    /// app appearance and which palette is edited below. There is no separate
    /// "Dark theme / Light theme" tab anymore — this one switch does both jobs.
    @Binding var appearance: Appearance

    /// One uniform rhythm for the whole editor (matches the rest of the settings).
    private let groupGap: CGFloat = 16
    private let rowGap: CGFloat = 16
    /// Fixed row height so every editor row keeps the same vertical pitch as the other sections.
    private let rowHeight: CGFloat = 26

    /// In System mode the app follows macOS, so editing the palette has no visible
    /// effect — the color/slider editors are disabled and dimmed to make that clear.
    private var isSystem: Bool { appearance == .system }

    private var editingDark: Bool {
        switch appearance {
        case .dark:   return true
        case .light:  return false
        case .system: return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: groupGap) {
            appearanceRow

            // ── Colors group ───────────────────────────────────────
            VStack(alignment: .leading, spacing: rowGap) {
                colorRow("Accent", \.accent)
                colorRow("Background", \.background)
                colorRow("Surface", \.surface)
                colorRow("Foreground", \.foreground)
            }
            .disabled(isSystem)
            .opacity(isSystem ? 0.4 : 1)

            // ── Text size (global, not per-palette) ─────────────────
            HStack {
                Text("Text size").font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                Spacer()
                TextField("", value: $theme.config.translationTextSize, formatter: Self.sizeFormatter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(width: 64, height: Theme.controlHeight)
                    .background(Capsule().fill(Theme.fieldFill))
                    .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))
                Text("px").font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }
            .frame(minHeight: rowHeight)

            // ── Sliders group (same inner rhythm as colors) ─────────
            VStack(alignment: .leading, spacing: rowGap) {
                sliderRow("Contrast", value: paletteDouble(\.contrast), range: 0...100)
                sliderRow("Background opacity", value: paletteDouble(\.backgroundOpacity), range: 0...100)
                sliderRow("Blur", value: paletteDouble(\.blur), range: 0...100)
            }
            .disabled(isSystem)
            .opacity(isSystem ? 0.4 : 1)
        }
    }

    /// Light / Dark / System segmented control — the only theme switcher in the app.
    private var appearanceRow: some View {
        HStack {
            Text("Appearance").font(.system(size: 12)).foregroundColor(Theme.textPrimary)
            Spacer()
            CapsuleSegmented(selection: $appearance, options: Appearance.allCases,
                             title: { $0.rawValue })
                .frame(width: 240)
        }
        .frame(minHeight: rowHeight)
    }

    private func paletteDouble(_ kp: WritableKeyPath<Palette, Double>) -> Binding<Double> {
        let pal = palette
        return Binding(get: { pal.wrappedValue[keyPath: kp] },
                       set: { pal.wrappedValue[keyPath: kp] = $0 })
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
            Spacer()
            GlowOrbSlider(value: value, range: range, step: 1)
                .frame(width: 180)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(minHeight: rowHeight)
    }

    private static let sizeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = 9
        f.maximum = 40
        f.maximumFractionDigits = 0
        return f
    }()

    private var palette: Binding<Palette> {
        editingDark ? $theme.config.dark : $theme.config.light
    }

    /// One row = one color. Writes STRICTLY into the currently-edited palette (dark or light),
    /// never the other one. Uses our inline color picker (ColorField).
    private func colorRow(_ label: String, _ kp: WritableKeyPath<Palette, String>) -> some View {
        let pal = palette
        let hexBinding = Binding<String>(
            get: { pal.wrappedValue[keyPath: kp] },
            set: { pal.wrappedValue[keyPath: kp] = $0 }
        )
        return ColorField(title: label, hex: hexBinding).frame(minHeight: rowHeight)
    }
}
