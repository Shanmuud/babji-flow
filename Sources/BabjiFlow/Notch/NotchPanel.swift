import AppKit
import SwiftUI
import Combine

enum NotchState: Equatable {
    case hidden
    case listening
    case locked          // hands-free
    case command         // command mode listening
    case processing(String)
    case done(String)
    case error(String)
    case downloading(Double, String)
    case meetingDetected(String)
    case meetingRecording
}

@MainActor
final class NotchController: ObservableObject {
    static let shared = NotchController()
    @Published var state: NotchState = .hidden
    @Published var level: Float = 0
    @Published var meetingElapsed: TimeInterval = 0
    /// Width of the physical notch on the chosen screen (0 when the screen has none).
    @Published var gap: CGFloat = 0
    @Published var barHeight: CGFloat = 38
    var onRecordMeeting: (() -> Void)?
    var onDismissMeeting: (() -> Void)?
    var onStopMeeting: (() -> Void)?

    private var panel: NSPanel!
    private var hideTimer: Timer?
    private var meetingTimer: Timer?
    private var meetingStart: Date?

    private init() {
        let hosting = NSHostingView(rootView: NotchView().environmentObject(self))
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .init(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.contentView = hosting
        p.ignoresMouseEvents = true
        panel = p
    }

    func show(_ s: NotchState, autoHideAfter: TimeInterval? = nil) {
        hideTimer?.invalidate()
        state = s
        switch s {
        case .meetingDetected, .meetingRecording, .error: panel.ignoresMouseEvents = false
        default: panel.ignoresMouseEvents = true
        }
        if case .meetingRecording = s {
            if meetingStart == nil { meetingStart = Date() }
            meetingTimer?.invalidate()
            meetingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.meetingElapsed = Date().timeIntervalSince(self?.meetingStart ?? Date()) }
            }
        } else if case .hidden = s {
            meetingTimer?.invalidate(); meetingStart = nil; meetingElapsed = 0
        }
        layout()
        panel.orderFrontRegardless()
        if let t = autoHideAfter {
            hideTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        state = .hidden
        meetingTimer?.invalidate(); meetingStart = nil; meetingElapsed = 0
        panel.orderOut(nil)
    }

    /// The screen the user is working on (keyboard focus), like Wispr's flow bar.
    private func targetScreen() -> NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    private func layout() {
        guard let screen = targetScreen() else { return }
        gap = 0
        barHeight = 44
        let width: CGFloat
        switch state {
        case .listening, .processing: width = 176
        case .locked, .command: width = 196
        case .downloading: width = 236
        case .done, .error: width = 340
        case .meetingDetected: width = 316
        case .meetingRecording: width = 206
        case .hidden: width = 0
        }
        let height = barHeight + 16   // room for Babji's head above the pill
        let x = screen.frame.midX - width / 2
        let y = screen.visibleFrame.minY + 18
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

struct NotchView: View {
    @EnvironmentObject var c: NotchController

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            pill.frame(height: c.barHeight)
            AnimatedBabji(mood: BabjiMood.forNotch(c.state), state: c.state, level: c.level)
                .frame(height: c.barHeight + 14)
                .padding(.leading, 6)
                .id(BabjiMood.forNotch(c.state))
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3, bounce: 0.2), value: BabjiMood.forNotch(c.state))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var pill: some View {
        ZStack {
            Capsule().fill(Color.black)
            // a whisper of light along the top edge, nothing else
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
            HStack(spacing: 8) {
                leading.frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.leading, 78).padding(.trailing, 14)
            .foregroundStyle(.white.opacity(0.92))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .contentTransition(.identity)
            .transaction { $0.animation = nil }   // labels switch instantly, no morphing
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    @ViewBuilder private var leading: some View {
        switch c.state {
        case .hidden: EmptyView()
        case .listening: Text("Listening").foregroundStyle(.white.opacity(0.7))
        case .locked: HStack(spacing: 5) { Text("Hands-free").foregroundStyle(.white.opacity(0.7)); Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }
        case .command: HStack(spacing: 5) { Image(systemName: "wand.and.stars").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white); Text("Command").foregroundStyle(.white.opacity(0.8)) }
        case .processing(let s): HStack(spacing: 6) { Dots(); Text(s).foregroundStyle(.white.opacity(0.6)) }
        case .done(let t): HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white); Text(t).lineLimit(1).truncationMode(.tail).foregroundStyle(.white.opacity(0.85)) }
        case .error(let e): HStack(spacing: 6) { Image(systemName: "exclamationmark.circle").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white); Text(e).lineLimit(1) }
        case .downloading(let p, let label):
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(width: 54, height: 3)
                    Capsule().fill(Color.white).frame(width: max(3, 54 * p), height: 3)
                }
                Text(label).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        case .meetingDetected(let app): HStack(spacing: 7) { Pulse(color: .white); Text(app.isEmpty ? "Meeting" : app).lineLimit(1) }
        case .meetingRecording: HStack(spacing: 7) { Pulse(color: .white); Text(format(c.meetingElapsed)).monospacedDigit() }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch c.state {
        case .meetingDetected:
            HStack(spacing: 5) {
                Button("Record") { c.onRecordMeeting?() }.buttonStyle(NotchButton(primary: true))
                Button { c.onDismissMeeting?() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(NotchButton(primary: false))
            }
        case .meetingRecording:
            Button("Stop") { c.onStopMeeting?() }.buttonStyle(NotchButton(primary: true))
        default: EmptyView()
        }
    }
    private func format(_ t: TimeInterval) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }
}

/// Babji is the animation: he bounces with your voice while listening, bobs while thinking,
/// pops when done, and shakes on errors.
struct AnimatedBabji: View {
    var mood: BabjiMood
    var state: NotchState
    var level: Float
    @State private var smoothed: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let lv = Double(level)
            let (scale, dy, rot): (Double, Double, Double) = {
                switch state {
                case .listening, .locked, .command:
                    // voice-driven bounce + a little sway
                    return (1 + lv * 0.22, -lv * 9 - abs(sin(t * 2.2)) * 1.5, sin(t * 3.1) * 3 * (0.3 + lv))
                case .processing, .downloading:
                    // thoughtful bob, head tilt
                    return (1 + 0.02 * sin(t * 2.4), sin(t * 2.4) * 2.2, -6 + sin(t * 1.3) * 2)
                case .done:
                    return (1.06, -2 + sin(t * 9) * 1.2, sin(t * 9) * 3)
                case .error:
                    return (1, 0, sin(t * 22) * 5)
                case .meetingDetected, .meetingRecording:
                    return (1 + 0.03 * sin(t * 1.8), sin(t * 1.8) * 1.5, 0)
                case .hidden:
                    return (1, 0, 0)
                }
            }()
            BabjiFace(mood: mood, height: 52)
                .scaleEffect(scale, anchor: .bottom)
                .rotationEffect(.degrees(rot), anchor: .bottom)
                .offset(y: dy)
                .animation(.spring(duration: 0.12, bounce: 0.3), value: level)
        }
    }
}

/// Three fading dots ("thinking").
struct Dots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.white).frame(width: 4, height: 4)
                        .opacity(0.25 + 0.75 * max(0, sin(t * 3 - Double(i) * 0.9)))
                }
            }
        }
    }
}

/// Breathing dot.
struct Pulse: View {
    var color: Color
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14).scaleEffect(on ? 1.4 : 0.8).opacity(on ? 0 : 0.8)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { on = true } }
    }
}

struct NotchButton: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(primary ? Color.white : Color.white.opacity(0.14))
            .foregroundStyle(primary ? Color.black : Color.white)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Minimal gradient waveform: 5 thin bars, smooth, driven by mic level with gentle idle motion.
struct LevelBars: View {
    var level: Float
    @State private var phase = 0.0
    private let n = 5
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<n, id: \.self) { i in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: height(i, t))
                }
            }
            .frame(height: 14)
        }
    }
    private func height(_ i: Int, _ t: Double) -> CGFloat {
        let center = Double(n - 1) / 2
        let envelope = 1 - abs(Double(i) - center) / (center + 1.2)   // taller in the middle
        let wobble = 0.5 + 0.5 * sin(t * 7 + Double(i) * 1.3)
        let amp = CGFloat(min(1, Double(level) * 1.6)) * 11 * CGFloat(envelope) * CGFloat(0.55 + 0.45 * wobble)
        return 3 + amp
    }
}
