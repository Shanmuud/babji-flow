import Foundation
import FluidAudio
import Combine

/// CTC keyword spotting + rescoring (NeMo CTC-WS, arXiv:2406.07096) so dictionary words are
/// recognised from the audio itself, not just patched afterwards. Loads a 97 MB CTC encoder once.
@MainActor
final class VocabularyBooster: ObservableObject {
    static let shared = VocabularyBooster()
    @Published private(set) var status = "off"
    private var ctc: CtcModels?
    private var session: VocabularyBoostingSession?
    private var builtFor: [String] = []
    private var loading = false
    private var sub: AnyCancellable?

    func start() {
        sub = DictionaryStore.shared.$entries.debounce(for: .seconds(1), scheduler: DispatchQueue.main).sink { [weak self] _ in
            Task { await self?.rebuild() }
        }
        Task { await rebuild() }
    }

    private func terms() -> [CustomVocabularyTerm] {
        DictionaryStore.shared.entries.map { e in
            CustomVocabularyTerm(text: e.word, weight: e.starred ? 1.5 : nil, aliases: e.misheard.isEmpty ? nil : e.misheard)
        }
    }

    private func rebuild() async {
        let words = DictionaryStore.shared.entries.map { $0.word + "|" + $0.misheard.joined(separator: ",") }
        guard words != builtFor else { return }
        guard !DictionaryStore.shared.entries.isEmpty else { session = nil; builtFor = words; status = "no words"; return }
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            if ctc == nil { status = "downloading CTC model"; ctc = try await CtcModels.downloadAndLoad(variant: .ctc110m) }
            status = "building"
            // Short personal vocabularies over-fire with the defaults (a 3-word list rewrote "hey are you free"
            // into names). Tight thresholds + no acoustic rescue pass: only clear misspellings of real terms get fixed.
            let vocab = CustomVocabularyContext(terms: terms(), minCtcScore: -6.0, minSimilarity: 0.62, minCombinedConfidence: 0.66, minTermLength: 4)
            let cfg = VocabularyRescorer.Config(spotterRescueMinSimilarity: 0.55, spotterRescueMultiWordMinSimilarity: 0.6, spotterRescueEnabled: false)
            session = try await VocabularyBoostingSession(vocabulary: vocab, ctcModels: ctc!, config: cfg)
            builtFor = words
            status = "on (\(DictionaryStore.shared.entries.count) words)"
        } catch {
            status = "failed: \(error.localizedDescription)"
            NSLog("Vocabulary boosting failed: %@", error.localizedDescription)
        }
    }

    /// Returns corrected text (or the input) plus the detected terms.
    func rescore(_ result: ASRResult, samples: [Float]) async -> (String, [String]) {
        guard let session, let timings = result.tokenTimings, !timings.isEmpty else { return (result.text, []) }
        guard let out = await session.rescore(text: result.text, tokenTimings: timings, audioSamples: samples) else { return (result.text, []) }
        return (out.wasModified ? out.text : result.text, out.detectedTerms)
    }
}

enum AudioPrep {
    /// Trim leading/trailing silence and peak-normalise so quiet mics still decode well.
    static func prepare(_ s: [Float]) -> [Float] {
        guard !s.isEmpty else { return s }
        var peak: Float = 0
        for v in s { peak = max(peak, abs(v)) }
        guard peak > 0.0005 else { return s }
        let gain = min(0.9 / peak, 20)
        var out = s.map { $0 * gain }
        // silence trim with 20 ms windows, keep 150 ms of padding
        let win = 320, pad = 2400
        func energy(_ i: Int) -> Float { var e: Float = 0; for j in i..<min(i + win, out.count) { e += out[j] * out[j] }; return e / Float(win) }
        let thr: Float = 0.0004
        var start = 0
        while start + win < out.count, energy(start) < thr { start += win }
        var end = out.count
        while end - win > start, energy(end - win) < thr { end -= win }
        start = max(0, start - pad); end = min(out.count, end + pad)
        if end - start > 8000 { out = Array(out[start..<end]) }
        return out
    }
}
