import Foundation
import FluidAudio

struct SpeakerSegment {
    var speaker: String
    var start: Double
    var end: Double
}

/// Offline speaker diarization over a 16 kHz mono track (pyannote segmentation + WeSpeaker embeddings).
final class SpeakerDiarizer {
    static let shared = SpeakerDiarizer()
    private var manager: DiarizerManager?

    func ensureLoaded(progress: ((String) -> Void)? = nil) async throws {
        if manager != nil { return }
        progress?("Downloading speaker model…")
        let models = try await DiarizerModels.downloadIfNeeded()
        var cfg = DiarizerConfig.default
        cfg.minSpeechDuration = 0.8
        cfg.clusteringThreshold = 0.7
        let m = DiarizerManager(config: cfg)
        m.initialize(models: models)
        manager = m
    }

    func diarize(_ samples: [Float]) throws -> [SpeakerSegment] {
        guard let manager else { return [] }
        let result = try manager.performCompleteDiarization(samples)
        return result.segments.map { SpeakerSegment(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
    }

    /// Dominant speaker in [start, end], or nil if nobody overlaps.
    static func speaker(for start: Double, end: Double, in segments: [SpeakerSegment]) -> String? {
        var best: (String, Double)? = nil
        for s in segments {
            let overlap = min(end, s.end) - max(start, s.start)
            if overlap > 0, best == nil || overlap > best!.1 { best = (s.speaker, overlap) }
        }
        return best?.0
    }
}
