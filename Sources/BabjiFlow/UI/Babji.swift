import SwiftUI
import AppKit

/// Babji, the mascot. Four moods, loaded from the bundled sticker pack.
enum BabjiMood: String, CaseIterable {
    case happy, speaking, thinking, angry

    static var cache: [BabjiMood: NSImage] = [:]
    var image: NSImage? {
        if let c = Self.cache[self] { return c }
        let candidates = [
            Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Babji"),
            Bundle.main.resourceURL?.appendingPathComponent("Babji/\(rawValue).png"),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Babji/\(rawValue).png"),
        ].compactMap { $0 }
        for u in candidates { if let img = NSImage(contentsOf: u) { Self.cache[self] = img; return img } }
        return nil
    }

    static func forNotch(_ s: NotchState) -> BabjiMood {
        switch s {
        case .listening, .locked, .command, .meetingRecording: return .speaking
        case .processing, .downloading: return .thinking
        case .done, .meetingDetected, .hidden: return .happy
        case .error: return .angry
        }
    }
}

/// Babji's face at a given height; keeps the sticker's aspect ratio.
struct BabjiFace: View {
    var mood: BabjiMood
    var height: CGFloat
    var body: some View {
        if let img = mood.image {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: height)
        } else {
            Circle().fill(Theme.accentGradient).frame(width: height, height: height)
                .overlay(Image(systemName: "face.smiling").foregroundStyle(.white))
        }
    }
}

/// Round avatar crop (for sidebar, cards).
struct BabjiAvatar: View {
    var mood: BabjiMood = .happy
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle().fill(Theme.heroGradient)
            if let img = mood.image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size * 1.35, height: size * 1.35).offset(y: size * 0.12)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}
