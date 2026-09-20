import Foundation
import AppKit
import Combine

/// Orchestrates hold-to-talk, hands-free lock, and Command Mode:
/// hotkey -> mic -> STT -> cleanup -> paste -> stats -> learn.
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
    private var targetPID: pid_t = 0
    private var context: (before: String, selected: String, after: String) = ("", "", "")
    private var commandTarget: CommandMode.Target?
    private var busy = false
    private var commandMode = false
    private var locked = false
    private var lastPressAt: Date?
    private var pressCount = 0
    private var cancelled = false
    var micMonitor: MicActivityMonitor?

    private init() {
        hotkey.onPress = { [weak self] cmd in self?.pressed(command: cmd) }
        hotkey.onRelease = { [weak self] in self?.released() }
        hotkey.onEscape = { [weak self] in self?.cancel() }
        levelSub = recorder.$level.receive(on: DispatchQueue.main).sink { NotchController.shared.level = $0 }
    }

    func start() { hotkey.start(); Transcriber.shared.ensureLoaded() }
    func restartHotkey() { hotkey.start() }

    // MARK: hotkey semantics (Wispr-style): hold = talk; double-tap within 0.5 s = hands-free lock;
    // a third tap (or any tap while locked) finishes; ESC cancels.
    private func pressed(command: Bool) {
        let now = Date()
        if let l = lastPressAt, now.timeIntervalSince(l) < 0.5 { pressCount += 1 } else { pressCount = 1 }
        lastPressAt = now
        if locked {                      // tap while locked -> finish
            finish(); return
        }
        if isListening { return }
        begin(command: command && Settings.shared.commandMode)
    }

    private func released() {
        guard isListening else { return }
        if pressCount >= 2, let l = lastPressAt, Date().timeIntervalSince(l) < 0.5 {
            // second quick tap -> lock hands-free
            locked = true
            NotchController.shared.show(commandMode ? .command : .locked)
            return
        }
        if locked { return }
        finish()
    }

    func cancel() {
        guard isListening else { return }
        cancelled = true
        _ = recorder.stop()
        micMonitor?.selfRecording = false
        isListening = false; locked = false; commandMode = false
        NotchController.shared.hide()
    }

    private func begin(command: Bool) {
        guard !isListening, !busy else { return }
        CorrectionLearner.shared.flush()
        let t = Transcriber.shared
        if !t.isReady {
            switch t.state {
            case .downloading(let p, let label): NotchController.shared.show(.downloading(p, label), autoHideAfter: 3)
            case .loading: NotchController.shared.show(.processing("Building"), autoHideAfter: 2)
            case .failed(let e): NotchController.shared.show(.error("Model failed: \(e)"), autoHideAfter: 4); t.ensureLoaded()
            default: t.ensureLoaded()
            }
            return
        }
        commandMode = command
        cancelled = false
        targetBundle = FrontmostApp.bundleID
        targetName = FrontmostApp.name
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if command {
            commandTarget = CommandMode.captureTarget(pid: targetPID)
        } else if Settings.shared.contextAwareness {
            context = FocusedField.readAround(pid: targetPID)
        } else {
            context = ("", "", "")
        }
        do {
            micMonitor?.selfRecording = true
            try recorder.start()
            isListening = true
            startedAt = Date()
            SoundCues.shared.play("start")
            NotchController.shared.show(command ? .command : .listening)
        } catch {
            micMonitor?.selfRecording = false
            NotchController.shared.show(.error("Mic unavailable: \(error.localizedDescription)"), autoHideAfter: 3)
        }
    }

    private func finish() {
        guard isListening else { return }
        isListening = false; locked = false
        let samples = recorder.stop()
        micMonitor?.selfRecording = false
        if cancelled { return }
        SoundCues.shared.play("stop")
        let seconds = Double(samples.count) / 16000
        guard seconds > 0.35 else { NotchController.shared.hide(); return }
        busy = true
        NotchController.shared.show(.processing("Thinking"))
        let bundle = targetBundle, appName = targetName ?? "Unknown"
        let isCommand = commandMode
        commandMode = false
        Task {
            defer { busy = false }
            do {
                let tr = try await Transcriber.shared.transcribe(samples)
                lastRaw = tr.text
                NSLog("Dictation raw (%.1fs): %@", seconds, tr.text)
                guard !tr.text.isEmpty else { NotchController.shared.show(.done("(nothing heard)"), autoHideAfter: 1.2); return }
                if isCommand, let target = commandTarget {
                    guard !target.selected.isEmpty else { NotchController.shared.show(.error("Select some text first"), autoHideAfter: 2); return }
                    guard LLM.hasKey else { NotchController.shared.show(.error(LLM.missingKeyMessage), autoHideAfter: 3); return }
                    NotchController.shared.show(.processing("Editing"))
                    let out = try await CommandMode.run(instruction: RuleCleaner.clean(tr.text), target: target, appName: appName)
                    let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { NotchController.shared.show(.error("Nothing to change"), autoHideAfter: 2); return }
                    CommandMode.replace(with: text, target: target)
                    lastResult = text
                    NotchController.shared.show(.done(text), autoHideAfter: 1.6)
                    return
                }
                var text = RuleCleaner.clean(tr.text)
                text = Normalizer.apply(text)
                text = DictionaryStore.shared.apply(to: text)
                text = SnippetStore.shared.apply(to: text)
                let category = Settings.shared.category(forBundle: bundle)
                let tone = Settings.shared.tone(for: category)
                if Settings.shared.autoCleanup {
                    NotchController.shared.show(.processing("Polishing"))
                    text = await StylePolisher.polish(text, tone: tone, category: category, appName: appName, context: context)
                } else {
                    text = StylePolisher.fallback(text, tone: tone)
                }
                text = DictionaryStore.shared.apply(to: text)
                // Continuation: if the field already ends mid-sentence, join naturally.
                let before = context.before
                if let last = before.last, !last.isNewline, !".!?:".contains(last), !RuleCleaner.wantsBullets(tr.text) {
                    let firstWord = text.split(separator: " ").first.map(String.init) ?? ""
                    let keepsCase = firstWord == "I" || firstWord.hasPrefix("I'") || DictionaryStore.shared.words.contains(where: { $0.caseInsensitiveCompare(firstWord) == .orderedSame })
                    if let f = text.first, f.isUppercase, !keepsCase { text = f.lowercased() + text.dropFirst() }
                    if !last.isWhitespace { text = " " + text }
                }
                lastResult = text
                NSLog("Dictation final [%@/%@]: %@", category.rawValue, tone.rawValue, text)
                TextInjector.paste(text)
                SoundCues.shared.play("done")
                CorrectionLearner.shared.didPaste(text)
                let words = text.split(whereSeparator: { $0.isWhitespace }).count
                StatsStore.shared.add(words: words, seconds: seconds, app: appName, category: category)
                NotchController.shared.show(.done(text), autoHideAfter: 1.6)
            } catch {
                SoundCues.shared.play("error")
                NotchController.shared.show(.error(error.localizedDescription), autoHideAfter: 3)
            }
        }
    }
}
