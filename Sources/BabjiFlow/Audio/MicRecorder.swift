import AVFoundation
import Combine

/// Captures the default microphone as 16 kHz mono Float32 samples and publishes a level meter.
final class MicRecorder: ObservableObject {
    @Published var level: Float = 0
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRunning = false
    /// Called with each new chunk of 16 kHz samples (for live processing).
    var onChunk: (([Float]) -> Void)?

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { c in
            AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
        }
    }

    func start() throws {
        guard !isRunning else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { throw NSError(domain: "Mic", code: 1, userInfo: [NSLocalizedDescriptionKey: "No input device"]) }
        converter = AVAudioConverter(from: inFormat, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return buffer
        }
        guard err == nil, out.frameLength > 0, let ch = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = sqrt(sum / Float(max(chunk.count, 1)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        onChunk?(chunk)
        DispatchQueue.main.async { self.level = min(1, rms * 8) }
    }

    /// Stops and returns all captured samples.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.lock(); let s = samples; samples = []; lock.unlock()
        DispatchQueue.main.async { self.level = 0 }
        return s
    }

    var durationSeconds: Double { lock.lock(); defer { lock.unlock() }; return Double(samples.count) / 16000 }
}
