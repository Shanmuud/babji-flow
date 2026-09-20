import SwiftUI

/// heyclicky-inspired: cream canvas, brushed-silver surfaces, soft pastel gradient accents, mac-native chrome.
enum Theme {
    static let bg = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 0.10, green: 0.10, blue: 0.105, alpha: 1) : NSColor(red: 0.985, green: 0.985, blue: 0.965, alpha: 1) })
    static let panel = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.155, alpha: 1) : .white })
    static let card = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 0.19, green: 0.19, blue: 0.195, alpha: 1) : NSColor(red: 0.955, green: 0.955, blue: 0.945, alpha: 1) })
    static let silverA = Color(red: 0.84, green: 0.835, blue: 0.843)
    static let silverB = Color(red: 0.94, green: 0.94, blue: 0.94)
    static let line = Color.primary.opacity(0.09)
    static let muted = Color.primary.opacity(0.5)
    static let ink = Color.primary
    static let blue = Color(red: 0, green: 0.53, blue: 1)
    static let teal = Color(red: 0, green: 0.76, blue: 0.82)
    static let mint = Color(red: 0, green: 0.78, blue: 0.70)
    static let coral = Color(red: 1, green: 0.4, blue: 0.4)
    static let amber = Color(red: 1, green: 0.55, blue: 0.16)
    static let accent = blue
    /// Signature accent gradient used for selection, waveform and highlights.
    static let accentGradient = LinearGradient(colors: [blue, teal, mint], startPoint: .leading, endPoint: .trailing)
    static let silverGradient = LinearGradient(colors: [silverA, silverB, silverA], startPoint: .leading, endPoint: .trailing)
    static let heroGradient = LinearGradient(stops: [
        .init(color: Color(red: 0.93, green: 0.95, blue: 1.0), location: 0),
        .init(color: Color(red: 0.92, green: 0.99, blue: 0.98), location: 0.5),
        .init(color: Color(red: 1.0, green: 0.96, blue: 0.93), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let titleFont = Font.system(size: 24, weight: .semibold, design: .rounded)
}

extension NSAppearance { var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua } }

/// Soft pastel-gradient hero panel (like heyclicky's tinted cards), dark text.
struct Hero<Content: View>: View {
    var title: String
    var subtitle: String
    var mascot: BabjiMood? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Color.black.opacity(0.85))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.black.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) { content }
            }
            .padding(22)
            .padding(.trailing, mascot == nil ? 0 : 150)
            .frame(maxWidth: .infinity, alignment: .leading)
            // decorative blobs
            Circle().fill(Theme.blue.opacity(0.18)).frame(width: 220, height: 220).blur(radius: 40).offset(x: 60, y: -90)
            Circle().fill(Theme.coral.opacity(0.14)).frame(width: 160, height: 160).blur(radius: 40).offset(x: -140, y: 40)
            if let mascot { BabjiFace(mood: mascot, height: 120).padding(.trailing, 18).frame(maxHeight: .infinity, alignment: .bottom).offset(y: 6) }
        }
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

/// Mac-window style card: white face, hairline silver edge, soft shadow.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct PageTitle: View {
    var text: String
    var body: some View { Text(text).font(Theme.titleFont).padding(.bottom, 4) }
}

/// Buttons: dark = ink pill; light = brushed-silver pill.
struct PillButton: ButtonStyle {
    var dark = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Group { if dark { Color.black.opacity(0.85) } else { Theme.silverGradient } })
            .foregroundStyle(dark ? Color.white : Color.black.opacity(0.8))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(dark ? 0 : 0.08)))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Tiny gradient dot used for status rows.
struct GradientDot: View {
    var ok: Bool
    var body: some View {
        Circle().fill(ok ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.amber)).frame(width: 8, height: 8)
    }
}
