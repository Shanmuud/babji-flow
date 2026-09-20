import Foundation
import AppKit
import Combine

/// Orchestrates hold-to-talk: hotkey -> mic -> STT -> cleanup -> paste -> stats -> learn.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()
    @Published private(set) var isListening = false
    @Published var lastResult: String = ""
    @Published var lastRaw: String = ""

    private let recorder = MicRecorder()
    private let hotkey = HotkeyMonitor()
    private var levelSub: AnyCancellable?
    private var startedAt: Date?
    private var targetBundle: String?
    private var targetName: String?
    private var busy = false
    var micMonitor: MicActivityMonitor?

    private init() {
        hotkey.onPress = { [weak self] in self?.begin() }
        hotkey.onRelease = { [weak self] in self?.finish() }
        levelSub = recorder.$level.receive(on: DispatchQueue.main).sink { NotchController.shared.level = $0 }
    }

    func start() {
        hotkey.start()
        Transcriber.shared.ensureLoaded()
    }
    func restartHotkey() { hotkey.start() }

    private func begin() {
        guard !isListening, !busy else { return }
        CorrectionLearner.shared.flush()
        let t = Transcriber.shared
        if !t.isReady {
            switch t.state {
            case .downloading(let p, let label): NotchController.shared.show(.downloading(p, label), autoHideAfter: 3)
            case .loading: NotchController.shared.show(.processing("Loading speech model…"), autoHideAfter: 2)
            case .failed(let e): NotchController.shared.show(.error("Model failed: \(e)"), autoHideAfter: 4); t.ensureLoaded()
            default: t.ensureLoaded()
            }
            return
        }
        targetBundle = FrontmostApp.bundleID
        targetName = FrontmostApp.name
        do {
            micMonitor?.selfRecording = true
            try recorder.start()
            isListening = true
            startedAt = Date()
            NotchController.shared.show(.listening)
        } catch {
            micMonitor?.selfRecording = false
            NotchController.shared.show(.error("Mic unavailable: \(error.localizedDescription)"), autoHideAfter: 3)
        }
    }

    private func finish() {
        guard isListening else { return }
        isListening = false
        let samples = recorder.stop()
        micMonitor?.selfRecording = false
        let seconds = Double(samples.count) / 16000
        guard seconds > 0.35 else { NotchController.shared.hide(); return }
        busy = true
        NotchController.shared.show(.processing("Transcribing…"))
        let bundle = targetBundle, appName = targetName ?? "Unknown"
        Task {
            defer { busy = false }
            do {
                let tr = try await Transcriber.shared.transcribe(samples)
                lastRaw = tr.text
                NSLog("Dictation raw (%.1fs): %@", seconds, tr.text)
                guard !tr.text.isEmpty else { NotchController.shared.show(.done("(nothing heard)"), autoHideAfter: 1.2); return }
                var text = RuleCleaner.clean(tr.text)
                text = Normalizer.apply(text)
                text = DictionaryStore.shared.apply(to: text)
                let category = Settings.shared.category(forBundle: bundle)
                let tone = Settings.shared.tone(for: category)
                if Settings.shared.autoCleanup {
                    NotchController.shared.show(.processing("Polishing…"))
                    text = await StylePolisher.polish(text, tone: tone, category: category)
                } else {
                    text = StylePolisher.fallback(text, tone: tone)
                }
                text = DictionaryStore.shared.apply(to: text)
                lastResult = text
                NSLog("Dictation final [%@/%@]: %@", category.rawValue, tone.rawValue, text)
                TextInjector.paste(text)
                CorrectionLearner.shared.didPaste(text)
                let words = text.split(whereSeparator: { $0.isWhitespace }).count
                StatsStore.shared.add(words: words, seconds: seconds, app: appName, category: category)
                NotchController.shared.show(.done(text), autoHideAfter: 1.6)
            } catch {
                NotchController.shared.show(.error(error.localizedDescription), autoHideAfter: 3)
            }
        }
    }
}
