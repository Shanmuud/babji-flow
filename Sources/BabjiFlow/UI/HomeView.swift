import SwiftUI

struct HomeView: View {
    @ObservedObject var stats = StatsStore.shared
    @ObservedObject var transcriber = Transcriber.shared
    @ObservedObject var dictation = DictationController.shared
    @ObservedObject var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(text: "Insights")
                Hero(title: "Hold \(settings.hotkey.label) and talk.", subtitle: statusLine, mascot: transcriber.isReady ? .speaking : .thinking) {
                    HStack(spacing: 8) {
                        StatusChip(ok: transcriber.isReady, label: modelLabel)
                        StatusChip(ok: Permissions.accessibilityGranted, label: Permissions.accessibilityGranted ? "Accessibility on" : "Accessibility needed")
                        StatusChip(ok: StylePolisher.appleAvailable || LLM.hasKey, label: polishLabel)
                    }
                }
                HStack(spacing: 12) {
                    Stat(value: fmt(stats.totalWords), label: "words dictated")
                    Stat(value: String(format: "%.0f", stats.averageWPM), label: "words / min")
                    Stat(value: fmtMinutes(stats.minutesSaved), label: "saved vs typing")
                    Stat(value: "\(stats.streakDays)d", label: "streak")
                }
                Card {
                    Text("LAST 30 DAYS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    DailyChart(data: stats.daily(30)).frame(height: 120)
                    Text("\(fmt(stats.wordsThisWeek)) words this week").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                HStack(alignment: .top, spacing: 12) {
                    Card {
                        Text("TOP APPS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        if stats.topApps.isEmpty { Text("Nothing yet. Dictate something!").foregroundStyle(Theme.muted).font(.system(size: 13)) }
                        ForEach(stats.topApps, id: \.0) { app, words in
                            HStack { Text(app).font(.system(size: 13)); Spacer(); Text(fmt(words)).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                        }
                    }
                    Card {
                        Text("LAST DICTATION").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        if dictation.lastResult.isEmpty { Text("Hold the hotkey in any text field.").foregroundStyle(Theme.muted).font(.system(size: 13)) }
                        else {
                            Text(dictation.lastResult).font(.system(size: 13)).textSelection(.enabled)
                            Text("heard: " + dictation.lastRaw).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(3)
                        }
                    }
                }
            }.padding(24)
        }
    }

    var statusLine: String {
        switch transcriber.state {
        case .ready: return "Speech runs fully on this Mac with Parakeet. Text is cleaned up in your style and pasted into the app you're in."
        case .downloading(let p, let l): return "\(l) \(Int(p * 100))%"
        case .loading: return "Loading the speech model…"
        case .failed(let e): return "Model failed to load: \(e)"
        case .idle: return "Starting…"
        }
    }
    var modelLabel: String {
        switch transcriber.state {
        case .ready: return "Parakeet \(settings.model.rawValue) ready"
        case .downloading(let p, let l): return (l.hasPrefix("Compiling") ? "Preparing model " : "Downloading ") + "\(Int(p * 100))%"
        case .loading: return "Loading model"
        case .failed: return "Model failed"
        case .idle: return "Model idle"
        }
    }
    var polishLabel: String {
        switch StylePolisher.resolveEngine() {
        case .apple: return "Apple Intelligence polish"
        case .claude: return "\(Settings.shared.provider.label) polish"
        case .none: return "Fluid-only cleanup"
        }
    }
    func fmt(_ n: Int) -> String { NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
    func fmtMinutes(_ m: Double) -> String { m >= 60 ? String(format: "%.1fh", m / 60) : String(format: "%.0fm", m) }
}

struct StatusChip: View {
    var ok: Bool; var label: String
    var body: some View {
        HStack(spacing: 6) { GradientDot(ok: ok); Text(label).font(.system(size: 12, weight: .medium)) }
            .padding(.horizontal, 10).padding(.vertical, 5).background(Color.white.opacity(0.7)).foregroundStyle(Color.black.opacity(0.8)).clipShape(Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.06)))
    }
}

struct Stat: View {
    var value: String; var label: String
    var body: some View {
        Card { Text(value).font(.system(size: 26, weight: .semibold)); Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted) }
    }
}

struct DailyChart: View {
    var data: [(Date, Int)]
    var body: some View {
        GeometryReader { g in
            let maxV = max(data.map(\.1).max() ?? 1, 1)
            let w = g.size.width / CGFloat(data.count)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(d.1 > 0 ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.line))
                        .frame(width: max(w - 2, 2), height: max(3, g.size.height * CGFloat(d.1) / CGFloat(maxV)))
                        .help("\(d.0.formatted(date: .abbreviated, time: .omitted)): \(d.1) words")
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
