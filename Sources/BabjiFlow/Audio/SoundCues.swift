import AVFoundation

/// Wispr-style audio cues: a soft rising tick when listening starts, a falling tick when it ends,
/// a two-note chime when text lands. Synthesised in memory, no assets.
final class SoundCues {
    static let shared = SoundCues()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.35
        buffers["start"] = tone([(660, 0.05), (990, 0.07)])
        buffers["stop"] = tone([(990, 0.05), (660, 0.07)])
        buffers["done"] = tone([(880, 0.06), (1320, 0.10)])
        buffers["error"] = tone([(330, 0.12)])
    }

    private func tone(_ notes: [(Double, Double)]) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let total = Int(notes.reduce(0) { $0 + $1.1 } * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buf.frameLength = AVAudioFrameCount(total)
        let p = buf.floatChannelData![0]
        var i = 0
        for (freq, dur) in notes {
            let n = Int(dur * sr)
            for k in 0..<n {
                let t = Double(k) / sr
                let env = min(1, Double(k) / (0.008 * sr)) * min(1, Double(n - k) / (0.03 * sr))  // soft attack/decay
                p[i] = Float(sin(2 * .pi * freq * t) * 0.6 * env + sin(2 * .pi * freq * 2 * t) * 0.08 * env)
                i += 1
            }
        }
        return buf
    }

    func play(_ name: String) {
        guard Settings.shared.soundCues, let b = buffers[name] else { return }
        do {
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying { player.play() }
            player.scheduleBuffer(b, at: nil, options: .interrupts)
        } catch { }
    }
}
