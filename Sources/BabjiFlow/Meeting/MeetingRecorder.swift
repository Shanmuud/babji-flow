import Foundation
import AVFoundation
import Combine

/// Records mic + system audio, transcribes in ~25 s chunks for a live transcript,
/// then diarizes the far side and assigns speakers at the end.
@MainActor
final class MeetingRecorder: ObservableObject {
    static let shared = MeetingRecorder()
    @Published private(set) var isRecording = false
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var status: String = ""
    @Published var current: Meeting?

    private let mic = MicRecorder()
    private let sys = SystemAudioCapture()
    private var micTrack: [Float] = []
    private var sysTrack: [Float] = []
    private var pendingMic: [Float] = []
    private var pendingSys: [Float] = []
    private var chunkStartSample = 0
    private var processed = 0
    private var chunkQueue: [(mic: [Float], sys: [Float], startSample: Int)] = []
    private var chunkWorker: Task<Void, Never>?
    private var flushTimer: Timer?
    private let lock = NSLock()
    private let chunkSeconds = 25
    var micMonitor: MicActivityMonitor?

    func start(app: String) async {
        guard !isRecording else { return }
        let t = Transcriber.shared
        t.ensureLoaded()
        micTrack = []; sysTrack = []; pendingMic = []; pendingSys = []; liveSegments = []; chunkStartSample = 0; processed = 0
        var m = Meeting(title: "Untitled", date: Date(), duration: 0, app: app)
        current = m
        micMonitor?.selfRecording = true
        mic.onChunk = { [weak self] c in self?.appendMic(c) }
        sys.onChunk = { [weak self] c in self?.appendSys(c) }
        do { try mic.start() } catch { status = "Mic failed: \(error.localizedDescription)" }
        do { try await sys.start() } catch {
            status = "System audio unavailable (grant Screen Recording in System Settings). Recording mic only."
        }
        isRecording = true
        m.title = "Meeting · \(app)"
        current = m
        NotchController.shared.show(.meetingRecording)
        flushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.maybeFlushChunk() }
        }
        chunkWorker = Task { await self.chunkLoop() }
    }

    nonisolated private func appendMic(_ c: [Float]) { lock.lock(); Task { @MainActor in self.pendingMic.append(contentsOf: c); self.micTrack.append(contentsOf: c) }; lock.unlock() }
    nonisolated private func appendSys(_ c: [Float]) { lock.lock(); Task { @MainActor in self.pendingSys.append(contentsOf: c); self.sysTrack.append(contentsOf: c) }; lock.unlock() }

    private func maybeFlushChunk(force: Bool = false) {
        let n = min(pendingMic.count, max(pendingSys.count, sys.isRunning ? 0 : Int.max))
        let need = chunkSeconds * 16000
        let available = sys.isRunning ? min(pendingMic.count, pendingSys.count) : pendingMic.count
        guard available >= need || (force && available > 8000) else { _ = n; return }
        let take = force ? available : need
        // Prefer to cut at a quiet point in the last 3 seconds of the chunk.
        var cut = take
        if !force {
            let win = 3 * 16000
            var bestIdx = take, bestE: Float = .greatestFiniteMagnitude
            var i = take - win
            while i < take - 1600 {
                var e: Float = 0
                for j in i..<(i + 1600) { let a = pendingMic[j] + (j < pendingSys.count ? pendingSys[j] : 0); e += a * a }
                if e < bestE { bestE = e; bestIdx = i + 800 }
                i += 800
            }
            cut = bestIdx
        }
        let m = Array(pendingMic.prefix(cut)); pendingMic.removeFirst(min(cut, pendingMic.count))
        let s = Array(pendingSys.prefix(cut)); pendingSys.removeFirst(min(cut, pendingSys.count))
        chunkQueue.append((m, s, chunkStartSample))
        chunkStartSample += cut
    }

    private func chunkLoop() async {
        while isRecording || !chunkQueue.isEmpty {
            if chunkQueue.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000); continue }
            let job = chunkQueue.removeFirst()
            await transcribeChunk(job)
        }
    }

    private func transcribeChunk(_ job: (mic: [Float], sys: [Float], startSample: Int)) async {
        guard Transcriber.shared.isReady else { chunkQueue.insert(job, at: 0); try? await Task.sleep(nanoseconds: 1_000_000_000); return }
        let n = max(job.mic.count, job.sys.count)
        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<n { mixed[i] = (i < job.mic.count ? job.mic[i] : 0) + (i < job.sys.count ? job.sys[i] : 0) }
        let offset = Double(job.startSample) / 16000
        guard let tr = try? await Transcriber.shared.transcribe(mixed, offset: offset), !tr.text.isEmpty else { return }
        // Split into sentences using word timings; mark speaker as "You" if mic energy dominates.
        let segs = Self.sentences(from: tr, mic: job.mic, sys: job.sys, base: offset)
        liveSegments.append(contentsOf: segs)
        current?.segments = liveSegments
    }

    /// Group words into sentence-ish segments and label mic-dominant ones "You".
    static func sentences(from tr: Transcription, mic: [Float], sys: [Float], base: Double) -> [TranscriptSegment] {
        guard !tr.words.isEmpty else {
            return [TranscriptSegment(speaker: energyLabel(mic: mic, sys: sys, from: 0, to: mic.count), start: base, end: base + Double(max(mic.count, sys.count)) / 16000, text: tr.text)]
        }
        var out: [TranscriptSegment] = []
        var cur: [TranscriptWord] = []
        func flush() {
            guard let f = cur.first, let l = cur.last else { return }
            let s0 = Int((f.start - base) * 16000), s1 = Int((l.end - base) * 16000)
            let label = energyLabel(mic: mic, sys: sys, from: max(0, s0), to: max(s0 + 1, s1))
            out.append(TranscriptSegment(speaker: label, start: f.start, end: l.end, text: cur.map(\.word).joined(separator: " ")))
            cur = []
        }
        for w in tr.words {
            if let last = cur.last, w.start - last.end > 1.2 { flush() }
            cur.append(w)
            if let c = w.word.last, ".!?".contains(c), cur.count >= 4 { flush() }
            if cur.count >= 40 { flush() }
        }
        flush()
        return out
    }

    static func energyLabel(mic: [Float], sys: [Float], from: Int, to: Int) -> String {
        func e(_ a: [Float]) -> Float {
            guard from < a.count else { return 0 }
            var s: Float = 0; for i in from..<min(to, a.count) { s += a[i] * a[i] }; return s
        }
        let em = e(mic), es = e(sys)
        if es == 0 && em == 0 { return "Speaker 1" }
        return em > es * 1.5 ? "You" : "Other"
    }

    func stop() async -> Meeting? {
        guard isRecording else { return nil }
        flushTimer?.invalidate(); flushTimer = nil
        _ = mic.stop()
        _ = await sys.stop()
        micMonitor?.selfRecording = false
        maybeFlushChunk(force: true)
        isRecording = false
        NotchController.shared.show(.processing("Finishing transcript…"))
        await chunkWorker?.value
        chunkWorker = nil
        guard var m = current else { return nil }
        m.duration = Double(max(micTrack.count, sysTrack.count)) / 16000
        // Save audio (mixed, 16 kHz WAV) for reference
        let name = "\(m.id.uuidString).wav"
        let n = max(micTrack.count, sysTrack.count)
        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<n { mixed[i] = (i < micTrack.count ? micTrack[i] : 0) + (i < sysTrack.count ? sysTrack[i] : 0) }
        if WavWriter.write(mixed, to: MeetingStore.audioDir.appendingPathComponent(name)) { m.audioFile = name }
        // Diarize the far side so "Other" becomes Speaker 2 / Speaker 3 ...
        NotchController.shared.show(.processing("Identifying speakers…"))
        if !sysTrack.isEmpty, sysTrack.count > 16000 * 3 {
            do {
                try await SpeakerDiarizer.shared.ensureLoaded()
                let sysCopy = sysTrack
                let segs = try await Task.detached { try SpeakerDiarizer.shared.diarize(sysCopy) }.value
                var map: [String: String] = [:]
                var next = 2
                for i in m.segments.indices where m.segments[i].speaker == "Other" {
                    if let sp = SpeakerDiarizer.speaker(for: m.segments[i].start, end: m.segments[i].end, in: segs) {
                        if map[sp] == nil { map[sp] = "Speaker \(next)"; next += 1 }
                        m.segments[i].speaker = map[sp]!
                    } else {
                        m.segments[i].speaker = "Speaker 2"
                    }
                }
            } catch {
                for i in m.segments.indices where m.segments[i].speaker == "Other" { m.segments[i].speaker = "Speaker 2" }
            }
        } else {
            for i in m.segments.indices where m.segments[i].speaker == "Other" { m.segments[i].speaker = "Speaker 2" }
        }
        m.segments = m.segments.map { var s = $0; s.text = DictionaryStore.shared.apply(to: Normalizer.apply(s.text)); return s }
        MeetingStore.shared.upsert(m)
        current = nil
        liveSegments = []
        micTrack = []; sysTrack = []
        NotchController.shared.show(.processing("Summarising…"))
        let summarised = await Summarizer.summarise(m)
        MeetingStore.shared.upsert(summarised)
        NotchController.shared.show(.done("Notes ready: \(summarised.title)"), autoHideAfter: 3)
        return summarised
    }
}

enum WavWriter {
    static func write(_ samples: [Float], to url: URL) -> Bool {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let file = try? AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatInt16, interleaved: true),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return false }
        buf.frameLength = AVAudioFrameCount(samples.count)
        guard let p = buf.int16ChannelData?[0] else { return false }
        for i in 0..<samples.count { p[i] = Int16(max(-1, min(1, samples[i])) * 32767) }
        return (try? file.write(from: buf)) != nil
    }
}
