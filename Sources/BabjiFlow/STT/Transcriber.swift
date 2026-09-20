import Foundation
import FluidAudio
import Combine

struct TranscriptWord {
    var word: String
    var start: Double
    var end: Double
}

struct Transcription {
    var text: String
    var words: [TranscriptWord]
    var confidence: Float
}

/// Wraps FluidAudio's Parakeet TDT models. Loads once, transcribes 16 kHz mono samples.
@MainActor
final class Transcriber: ObservableObject {
    static let shared = Transcriber()

    enum State: Equatable {
        case idle, downloading(Double, String), loading, ready, failed(String)
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var loadedVersion: ModelChoice?

    private var manager: AsrManager?
    private var loadTask: Task<Void, Never>?

    var isReady: Bool { if case .ready = state { return true } else { return false } }

    func ensureLoaded() {
        let wanted = Settings.shared.model
        if isReady, loadedVersion == wanted { return }
        if loadTask != nil, loadedVersion == nil { return }
        loadTask?.cancel()
        loadTask = Task { await load(version: wanted) }
    }

    private func load(version: ModelChoice) async {
        state = .downloading(0, "Getting ready")
        let asrVersion: AsrModelVersion = version == .v2 ? .v2 : .v3
        do {
            let models = try await AsrModels.downloadAndLoad(version: asrVersion, progressHandler: { p in
                let label: String
                switch p.phase {
                case .listing: label = "Getting ready"
                case .downloading: label = "Downloading voice"
                case .compiling: label = "Building"
                }
                Task { @MainActor in
                    if case .downloading(let old, let oldLabel) = self.state, oldLabel == label, abs(p.fractionCompleted - old) < 0.01 { return }
                    self.state = .downloading(p.fractionCompleted, label)
                }
            })
            state = .loading
            let m = AsrManager(config: .default)
            try await m.loadModels(models)
            manager = m
            loadedVersion = version
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            manager = nil
        }
        loadTask = nil
    }

    /// Transcribe 16 kHz mono samples. `offset` shifts word timestamps (for chunked meetings).
    func transcribe(_ samples: [Float], offset: Double = 0) async throws -> Transcription {
        guard let manager else { throw NSError(domain: "STT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech model not loaded yet"]) }
        // Pad very short clips so the encoder has enough context.
        var s = samples
        if s.count < 16000 { s.append(contentsOf: [Float](repeating: 0, count: 16000 - s.count)) }
        let layers = await manager.decoderLayerCount
        var state = try TdtDecoderState(decoderLayers: layers)
        let result = try await manager.transcribe(s, decoderState: &state)
        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TranscriptWord(word: $0.word, start: $0.startTime + offset, end: $0.endTime + offset)
        }
        return Transcription(text: result.text.trimmingCharacters(in: .whitespacesAndNewlines), words: words, confidence: result.confidence)
    }
}
