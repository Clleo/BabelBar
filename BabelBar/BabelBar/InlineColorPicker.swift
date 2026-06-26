import SwiftUI
import AppKit

// A self-contained inline color picker (saturation/brightness square + hue slider + hex),
// shown in a SwiftUI popover anchored next to the setting — no floating system color panel.

/// A labelled swatch that opens the inline picker in an anchored popover.
struct ColorField: View {
    let title: String
    @Binding var hex: String
    @State private var open = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
            Spacer()
            Text(hex.uppercased())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
            Button { open.toggle() } label: {
                Capsule(style: .continuous)
                    .fill(Color(hex: hex))
                    .frame(width: 46, height: Theme.controlHeight)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(hover ? Theme.textPrimary.opacity(0.4) : Theme.controlBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                InlineColorPicker(hex: $hex)
                    .padding(14)
                    .frame(width: 248)
            }
        }
    }
}

struct InlineColorPicker: View {
    @Binding var hex: String

    @State private var hue: Double = 0
    @State private var sat: Double = 1
    @State private var bri: Double = 1
    @State private var hexText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            svSquare
            hueSlider
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hue: hue, saturation: sat, brightness: bri))
                    .frame(width: 28, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))
                TextField("#RRGGBB", text: $hexText, onCommit: commitHex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        .onAppear(perform: load)
    }

    // Saturation (x) × Brightness (y) square for the current hue.
    private var svSquare: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .position(x: sat * w, y: (1 - bri) * h)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                sat = clamp(v.location.x / w)
                bri = 1 - clamp(v.location.y / h)
                push()
            })
        }
        .frame(height: 150)
    }

    private var hueSlider: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6.0).map {
                        Color(hue: $0, saturation: 1, brightness: 1)
                    },
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(Capsule())
                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .position(x: hue * w, y: 8)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                hue = clamp(v.location.x / w)
                push()
            })
        }
        .frame(height: 16)
    }

    private func clamp(_ x: CGFloat) -> Double { Double(min(max(x, 0), 1)) }

    private func load() {
        let ns = NSColor(Color(hex: hex)).usingColorSpace(.deviceRGB) ?? .black
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); sat = Double(s); bri = Double(b)
        hexText = hex.uppercased()
    }

    private func push() {
        hex = Color(hue: hue, saturation: sat, brightness: bri).toHex()
        hexText = hex.uppercased()
    }

    private func commitHex() {
        let s = hexText.hasPrefix("#") ? hexText : "#" + hexText
        hex = s
        load()
    }
}
