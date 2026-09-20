import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Captures audio played by other apps (the far side of a call) via ScreenCaptureKit,
/// converted to 16 kHz mono Float32. Requires Screen Recording permission.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let queue = DispatchQueue(label: "babji.sysaudio")
    private var samples: [Float] = []
    private let lock = NSLock()
    var onChunk: (([Float]) -> Void)?
    private(set) var isRunning = false

    func start() async throws {
        guard !isRunning else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw NSError(domain: "SysAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display"]) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48000
        cfg.channelCount = 1
        cfg.width = 2; cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        cfg.showsCursor = false
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        isRunning = true
        lock.withLock { samples.removeAll() }
    }

    func stop() async -> [Float] {
        guard isRunning, let s = stream else { return [] }
        try? await s.stopCapture()
        stream = nil; isRunning = false
        return lock.withLock { let out = samples; samples = []; return out }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let fmtDesc = sampleBuffer.formatDescription,
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return }
        var asbd = asbdPtr.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &asbd) else { return }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        var blockBuffer: CMBlockBuffer?
        let abl = pcm.mutableAudioBufferList
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size + Int(inFormat.channelCount - 1) * MemoryLayout<AudioBuffer>.size,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)
        guard status == noErr else { return }
        if converter == nil || converter?.inputFormat != inFormat { converter = AVAudioConverter(from: inFormat, to: targetFormat) }
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / inFormat.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(Double(frames) * ratio) + 16) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, st in
            if consumed { st.pointee = .noDataNow; return nil }
            consumed = true; st.pointee = .haveData; return pcm
        }
        guard err == nil, out.frameLength > 0, let ch = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        onChunk?(chunk)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
    }
}
