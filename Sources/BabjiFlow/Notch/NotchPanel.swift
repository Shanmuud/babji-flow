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

    /// Prefer the built-in display with a notch; otherwise fall back to the main screen as a floating pill.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func layout() {
        guard let screen = targetScreen() else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        if hasNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            gap = max(0, screen.frame.width - l.width - r.width)
            barHeight = screen.safeAreaInsets.top
        } else {
            gap = 0
            barHeight = 34
        }
        // How far the pill extends beyond each side of the notch.
        let side: CGFloat
        switch state {
        case .listening, .locked, .command: side = 66
        case .processing: side = 58
        case .downloading: side = 96
        case .done, .error: side = 150
        case .meetingDetected: side = 168
        case .meetingRecording: side = 96
        case .hidden: side = 0
        }
        let width = gap + side * 2 + (gap == 0 ? 40 : 0)
        let height = barHeight + 12                                // Babji's chin dips just below the bar
        let x = screen.frame.midX - width / 2
        panel.setFrame(NSRect(x: x, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }
}

struct NotchView: View {
    @EnvironmentObject var c: NotchController

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 14, bottomTrailing: 14, topTrailing: 0))
    }

    var body: some View {
        ZStack(alignment: .top) {
            pill.frame(height: c.barHeight + 4)
            // Babji peeks over the bottom edge of the pill, hands on the ledge.
            HStack { Spacer(); BabjiFace(mood: BabjiMood.forNotch(c.state), height: c.barHeight + 4).padding(.trailing, 8) }
                .frame(height: c.barHeight + 12, alignment: .bottom)
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                .id(BabjiMood.forNotch(c.state))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: c.state)
    }

    private var pill: some View {
        ZStack {
            shape.fill(Color.black)
            // soft colour wash on the right, like a glow leaking out of the notch
            shape.fill(LinearGradient(colors: [.clear, .clear, tint.opacity(0.28)], startPoint: .leading, endPoint: .trailing))
                .blur(radius: 8).padding(3).mask(shape)
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
            HStack(spacing: 0) {
                leading.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                if c.gap > 0 { Color.clear.frame(width: c.gap) }
                trailing.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 48)
            }
            .frame(height: c.barHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white.opacity(0.92))
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
        }
    }

    private var tint: Color {
        switch c.state {
        case .listening: return Theme.teal
        case .locked: return Theme.mint
        case .command: return Color(red: 1, green: 0.62, blue: 0.2)
        case .processing, .downloading: return Color(red: 0.62, green: 0.2, blue: 0.9)
        case .done: return Theme.mint
        case .error, .meetingDetected, .meetingRecording: return Theme.coral
        case .hidden: return .clear
        }
    }

    @ViewBuilder private var leading: some View {
        switch c.state {
        case .hidden: EmptyView()
        case .listening: LevelBars(level: c.level)
        case .locked: HStack(spacing: 6) { LevelBars(level: c.level); Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)) }
        case .command: HStack(spacing: 6) { Image(systemName: "wand.and.stars").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.3)); LevelBars(level: c.level) }
        case .processing: Dots()
        case .done(let t): HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.mint); Text(t).lineLimit(1).truncationMode(.tail) }
        case .error(let e): HStack(spacing: 6) { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.coral); Text(e).lineLimit(1) }
        case .downloading(let p, _):
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(width: 54, height: 3)
                    Capsule().fill(Theme.accentGradient).frame(width: max(3, 54 * p), height: 3)
                }
                Text("Building").foregroundStyle(.white.opacity(0.7))
            }
        case .meetingDetected(let app): HStack(spacing: 7) { Pulse(color: Theme.coral); Text(app.isEmpty ? "Meeting" : app).lineLimit(1) }
        case .meetingRecording: HStack(spacing: 7) { Pulse(color: Theme.coral); Text(format(c.meetingElapsed)).monospacedDigit() }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch c.state {
        case .hidden, .done, .error, .listening, .locked, .command, .processing, .downloading: EmptyView()
        case .meetingDetected:
            HStack(spacing: 5) {
                Button("Record") { c.onRecordMeeting?() }.buttonStyle(NotchButton(primary: true))
                Button { c.onDismissMeeting?() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(NotchButton(primary: false))
            }
        case .meetingRecording:
            Button("Stop") { c.onStopMeeting?() }.buttonStyle(NotchButton(primary: true))
        }
    }
    private func format(_ t: TimeInterval) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }
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
            .background(Group { if primary { AnyView(Theme.accentGradient) } else { AnyView(Color.white.opacity(0.12)) } })
            .foregroundStyle(Color.white)
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
                        .fill(Theme.accentGradient)
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
