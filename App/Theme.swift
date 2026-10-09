import SwiftUI
import BrinkCore

/// Visual language: a field report printed on dark paper. Warm charcoal ground, paper-white type,
/// hairlines instead of boxes, one bone-white for action; colour belongs to the 3D scenes and to
/// real states (danger, warning, fine), not to decoration (D-048).
enum Theme {
    static let bg = Color(red: 0.075, green: 0.071, blue: 0.063)        // #13120F charcoal
    static let panel = Color(red: 0.098, green: 0.094, blue: 0.086)     // #191816
    static let panelHi = Color(red: 0.129, green: 0.122, blue: 0.110)   // #211F1C
    static let line = Color(red: 0.180, green: 0.169, blue: 0.153)      // #2E2B27 hairlines
    static let text = Color(red: 0.910, green: 0.890, blue: 0.851)      // #E8E3D9 paper
    static let dim = Color(red: 0.639, green: 0.616, blue: 0.573)       // #A39D92
    static let faint = Color(red: 0.435, green: 0.416, blue: 0.380)     // #6F6A61
    static let flare = Color(red: 0.886, green: 0.827, blue: 0.710)     // #E2D3B5 bone: action, focus
    static let danger = Color(red: 0.761, green: 0.357, blue: 0.290)    // #C25B4A brick
    static let warn = Color(red: 0.769, green: 0.604, blue: 0.322)      // #C49A52 ochre
    static let good = Color(red: 0.545, green: 0.635, blue: 0.482)      // #8BA27B sage
    static let secret = Color(red: 0.557, green: 0.612, blue: 0.702)    // #8E9CB3 ink: private, god view

    static let serif = "Songti SC"

    // Songti for Chinese; for English the system serif (New York), which sets Latin text and "°C" properly
    static func title(_ size: CGFloat) -> Font {
        Loc.ui == .en ? .system(size: size, weight: .bold, design: .serif) : .custom(serif, size: size).weight(.bold)
    }
    static func prose(_ size: CGFloat) -> Font {
        Loc.ui == .en ? .system(size: size, design: .serif) : .custom(serif, size: size)
    }

    static func accent(_ s: Scenario?) -> Color {
        guard let hex = s?.accent else { return flare }
        return Color(hex: hex) ?? flare
    }

    /// Stable color per character id.
    static func person(_ id: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.62, green: 0.70, blue: 0.78), Color(red: 0.79, green: 0.60, blue: 0.53),
            Color(red: 0.62, green: 0.69, blue: 0.55), Color(red: 0.80, green: 0.71, blue: 0.50),
            Color(red: 0.66, green: 0.61, blue: 0.74), Color(red: 0.55, green: 0.71, blue: 0.68),
            Color(red: 0.78, green: 0.58, blue: 0.65)
        ]
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }

    static func tone(_ t: String) -> Color {
        switch t {
        case "good": return good
        case "bad": return danger
        default: return warn
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 0.5))
    }
}

/// Small heading. Letter-spaced in English only: Chinese doesn't take tracking.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(Loc.ui == .en ? text.uppercased() : text)
            .font(.system(size: Loc.ui == .en ? 10 : 11, weight: .semibold))
            .tracking(Loc.ui == .en ? 1.1 : 0)
            .foregroundStyle(Theme.faint)
    }
}

struct Meter: View {
    let value: Double   // 0...1
    let color: Color
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.line)
                Rectangle().fill(color).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

/// A state written on a tag: outlined, never filled.
struct Chip: View {
    let text: String
    var color: Color = Theme.dim
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.45), lineWidth: 0.75))
    }
}

/// An initial in a thin ring: the person's colour marks them without turning the screen into a chat app.
struct Avatar: View {
    let id: String
    let name: String
    var size: CGFloat = 30
    var dead = false
    var body: some View {
        let c = dead ? Theme.faint : Theme.person(id)
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(c)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(c.opacity(dead ? 0.5 : 0.7), lineWidth: 1))
    }
}

/// The one solid button: bone-white with dark type (or a state colour when given one).
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.flare
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, color: color)
    }
}

/// Reads whether the button is enabled (a ButtonStyle can't), so a disabled primary button looks it.
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let color: Color
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(enabled ? Theme.bg : Theme.faint)
            .background((enabled ? color : Theme.panelHi).opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 3))
    }
}

/// Secondary actions: a hairline outline.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.text.opacity(configuration.isPressed ? 0.7 : 1))
            .background(configuration.isPressed ? Theme.panelHi : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line.opacity(1.6), lineWidth: 1))
    }
}
