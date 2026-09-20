import SwiftUI
import AppKit

struct StyleView: View {
    @ObservedObject var settings = Settings.shared
    @State private var category: StyleCategory = .personal
    @State private var showCleanup = false
    @State private var pickApp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(text: "Style")
                HStack(spacing: 18) {
                    ForEach(StyleCategory.allCases) { c in Tab(label: c.label, on: !showCleanup && category == c) { category = c; showCleanup = false } }
                    HStack(spacing: 6) { Tab(label: "Auto cleanup", on: showCleanup) { showCleanup = true }; Text("Beta").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent.opacity(0.15)).foregroundStyle(Theme.accent).clipShape(Capsule()) }
                    Spacer()
                }
                if showCleanup { cleanup } else { styleCards }
            }.padding(24)
        }
        .sheet(isPresented: $pickApp) { AppPicker(category: category) }
    }

    var styleCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            Hero(title: category.blurb, subtitle: "Babji detects the app you're typing into and applies this style. Style formatting only applies in English.") {
                HStack(spacing: -8) {
                    ForEach(apps(for: category), id: \.self) { b in AppIcon(bundle: b) }
                    if apps(for: category).isEmpty { Text("No apps assigned yet").font(.system(size: 12)).foregroundStyle(Color.black.opacity(0.5)).padding(.trailing, 12) }
                    Button { pickApp = true } label: { Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 40, height: 40).background(Theme.silverGradient).clipShape(Circle()).overlay(Circle().stroke(Color.white, lineWidth: 2)) }.buttonStyle(.plain).foregroundStyle(Color.black.opacity(0.7))
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Tone.allCases) { t in
                    ToneCard(tone: t, selected: settings.tone(for: category) == t) { settings.tones[category] = t }
                }
            }
            Card {
                Text("HOW YOU WRITE (optional)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                Text("Paste a few messages you've actually sent. The AI polish will mimic your phrasing, slang and punctuation habits.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                TextEditor(text: $settings.styleSample).font(.system(size: 13)).frame(height: 90).scrollContentBackground(.hidden).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    var cleanup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Toggle("Extra AI polish on top of Fluid", isOn: $settings.autoCleanup).font(.system(size: 14, weight: .medium))
                Text("Always on (offline, FluidAudio): Parakeet punctuation and casing, filler removal, spoken commands ('new line', 'bullet point', 'scratch that'), NeMo number/time/money normalisation, dictionary and tone. Optional AI polish adds grammar fixes and finer style matching.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                StatusRow(ok: Normalizer.isAvailable, text: Normalizer.isAvailable ? "NeMo text normaliser linked (nineteen thousand → 19,000)" : "NeMo text normaliser missing")
                Picker("Engine", selection: $settings.polishEngine) { ForEach(PolishEngine.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu)
                HStack(spacing: 8) {
                    StatusRow(ok: StylePolisher.appleAvailable, text: StylePolisher.appleAvailable ? "Apple Intelligence available on this Mac (free, on-device)" : (StylePolisher.appleUnavailableReason ?? "Apple Intelligence not available."))
                }
                StatusRow(ok: LLM.hasKey, text: LLM.hasKey ? "\(settings.provider.label) key set" : "No \(settings.provider.label) key (optional for dictation, required for meeting summaries)")
                Toggle("Learn from my corrections automatically", isOn: $settings.autoLearn).font(.system(size: 13))
            }
            Card {
                Text("SPOKEN COMMANDS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                ForEach([("new line / new paragraph", "line break / blank line"), ("bullet point / next point", "starts a new '- ' line"), ("scratch that / no wait", "drops what you just said"), ("in points / as a list", "formats the whole thing as bullets"), ("question mark / full stop", "inserts punctuation")], id: \.0) { c in
                    HStack { Text(c.0).font(.system(size: 13, design: .monospaced)); Spacer(); Text(c.1).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                }
            }
        }
    }

    /// Only apps actually installed on this Mac, so the row never shows placeholder letters.
    func apps(for c: StyleCategory) -> [String] {
        settings.appCategories.filter { $0.value == c }.map(\.key).sorted()
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }
}

struct StatusRow: View {
    var ok: Bool; var text: String
    var body: some View { HStack(spacing: 6) { GradientDot(ok: ok); Text(text).font(.system(size: 12)).foregroundStyle(Theme.muted) } }
}

struct ToneCard: View {
    var tone: Tone; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tone.title).font(.system(size: 14, weight: .medium))
                Text(tone.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer(minLength: 20)
                Text(tone.sample).font(.system(size: 12.5)).padding(12).background(Theme.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack { Spacer(); BabjiAvatar(mood: selected ? .happy : .thinking, size: 36).opacity(selected ? 1 : 0.55) }
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.line), lineWidth: selected ? 2 : 1))
            .shadow(color: .black.opacity(selected ? 0.08 : 0.03), radius: 8, y: 2)
        }.buttonStyle(.plain)
    }
}

struct AppIcon: View {
    var bundle: String
    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Text(String(bundle.split(separator: ".").last?.prefix(1) ?? "?")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black.opacity(0.6))
            }
        }
        .frame(width: 40, height: 40).background(Color.white).clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2)).shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .help(bundle)
    }
}

struct AppPicker: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var settings = Settings.shared
    var category: StyleCategory
    var running: [NSRunningApplication] { NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps using the \(category.label.lowercased()) style").font(.headline)
            Text("Click a running app to assign it. Click again to remove.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(running, id: \.processIdentifier) { app in
                        let b = app.bundleIdentifier!
                        let assigned = settings.appCategories[b]
                        Button {
                            if assigned == category { settings.appCategories.removeValue(forKey: b) } else { settings.appCategories[b] = category }
                        } label: {
                            HStack { if let i = app.icon { Image(nsImage: i).resizable().frame(width: 20, height: 20) }; Text(app.localizedName ?? b); Spacer()
                                if let a = assigned { Text(a.label).font(.system(size: 11)).foregroundStyle(a == category ? Theme.accent : Theme.muted) } }
                            .padding(6).background(assigned == category ? Theme.accent.opacity(0.12) : .clear).clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 300)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 420)
    }
}
