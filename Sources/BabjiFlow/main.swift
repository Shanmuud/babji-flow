import Foundation
import AVFoundation

// Headless helpers for testing without the UI:
//   BabjiFlow --transcribe file.wav [--tone casual] [--category personal]
//   BabjiFlow --clean "raw text"
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--engine"), i + 1 < args.count, let e = PolishEngine(rawValue: args[i + 1]) {
    let previous = Settings.shared.polishEngine
    Settings.shared.polishEngine = e
    atexit_b { Settings.shared.polishEngine = previous; UserDefaults.standard.synchronize() }
}
if let i = args.firstIndex(of: "--add-word"), i + 1 < args.count {
    let parts = args[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
    DictionaryStore.shared.add(word: parts[0], misheard: parts.count > 1 ? parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : [])
    print("added \(parts[0]); dictionary now \(DictionaryStore.shared.entries.count) words")
    exit(0)
} else if let i = args.firstIndex(of: "--set-openai-key"), i + 1 < args.count {
    Settings.shared.setOpenAIKey(args[i + 1]); Settings.shared.provider = .openai
    print("OpenAI key stored: \(Settings.shared.hasOpenAIKey)")
    exit(0)
} else if let i = args.firstIndex(of: "--set-key"), i + 1 < args.count {
    Settings.shared.setClaudeKey(args[i + 1])
    print("Claude key stored: \(Settings.shared.hasClaudeKey)")
    exit(0)
} else if let i = args.firstIndex(of: "--summarize"), i + 1 < args.count {
    let text = (try? String(contentsOfFile: args[i + 1], encoding: .utf8)) ?? ""
    var m = Meeting(title: "Test", date: Date(), duration: 600, app: "Test")
    var t = 0.0
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { continue }
        m.segments.append(TranscriptSegment(speaker: parts[0], start: t, end: t + 5, text: parts[1])); t += 5
    }
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let out = await Summarizer.summarise(m)
        if let e = out.summaryError { print("error: \(e)") }
        if let s = out.summary {
            print("TITLE: \(s.title)\nOVERVIEW: \(s.overview)\n")
            for sec in s.sections { print(sec.heading); for b in sec.bullets { print("  • \(b)") }; print() }
            print("Next steps"); for st in s.nextSteps { print("  • (\(st.owner)) \(st.action)") }
            print("\nDecisions"); for d in s.decisions { print("  • \(d)") }
            print("\nSpeaker names: \(out.speakerNames)")
        }
        if args.contains("--chat") {
            var hist = [ChatTurn(role: "user", text: "What should Speaker 5 do first this week, and why?")]
            var full = ""
            do { for try await c in TranscriptChat.ask(out, history: hist) { full += c } } catch { full = "chat error: \(error)" }
            print("\nCHAT: \(full)"); hist.append(ChatTurn(role: "assistant", text: full))
        }
        sem.signal()
    }
    while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)
} else if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
    let url = URL(fileURLWithPath: args[i + 1])
    let tone = Tone(rawValue: args.firstIndex(of: "--tone").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "casual") ?? .casual
    let category = StyleCategory(rawValue: args.firstIndex(of: "--category").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "other") ?? .other
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        do {
            let file = try AVAudioFile(forReading: url)
            let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw NSError(domain: "cli", code: 1) }
            try file.read(into: inBuf)
            let conv = AVAudioConverter(from: file.processingFormat, to: fmt)!
            let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(file.length) * 16000 / file.processingFormat.sampleRate) + 16)!
            var used = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, st in if used { st.pointee = .noDataNow; return nil }; used = true; st.pointee = .haveData; return inBuf }
            let samples = Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
            print("audio: \(Double(samples.count) / 16000)s")
            Transcriber.shared.ensureLoaded()
            VocabularyBooster.shared.start()
            while !Transcriber.shared.isReady {
                if case .failed(let e) = Transcriber.shared.state { print("model failed: \(e)"); exit(1) }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            var waited = 0
            while ["building", "downloading CTC model"].contains(VocabularyBooster.shared.status) || (VocabularyBooster.shared.status == "off" && !DictionaryStore.shared.entries.isEmpty && waited < 200) {
                try await Task.sleep(nanoseconds: 300_000_000); waited += 1
            }
            print("boost: \(VocabularyBooster.shared.status)")
            let t0 = Date()
            let tr = try await Transcriber.shared.transcribe(samples)
            print("raw (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s, conf \(tr.confidence)): \(tr.text)")
            print("words: \(tr.words.count), first: \(tr.words.first.map { "\($0.word)@\($0.start)" } ?? "-")")
            var text = RuleCleaner.clean(tr.text)
            print("rules: \(text)")
            text = Normalizer.apply(text)
            print("itn (\(Normalizer.isAvailable ? "NeMo" : "unavailable")): \(text)")
            text = DictionaryStore.shared.apply(to: text)
            print("engine: \(StylePolisher.resolveEngine()) apple=\(StylePolisher.appleUnavailableReason ?? "available")")
            let polished = await StylePolisher.polish(text, tone: tone, category: category)
            print("final [\(category.rawValue)/\(tone.rawValue)]: \(polished)")
        } catch { print("error: \(error)") }
        sem.signal()
    }
    while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)
} else if let i = args.firstIndex(of: "--clean"), i + 1 < args.count {
    let raw = args[i + 1]
    var text = RuleCleaner.clean(raw)
    text = Normalizer.apply(text)
    text = DictionaryStore.shared.apply(to: text)
    print("rules: \(text)")
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        print("final: \(await StylePolisher.polish(text, tone: .casual, category: .other))")
        sem.signal()
    }
    while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)
} else {
    BabjiFlowApp.main()
}
