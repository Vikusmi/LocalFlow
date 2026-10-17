import AVFoundation

/// Records the default microphone into 16 kHz mono Float samples (what Whisper expects).
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    /// Called on the main thread with the current input level, 0…1.
    var onLevel: ((Float) -> Void)?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "LocalFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported microphone format"])
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and returns everything captured.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = output.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: data, count: Int(output.frameLength))
        lock.withLock { samples.append(contentsOf: chunk) }
        reportLevel(chunk)
    }

    private func reportLevel(_ chunk: UnsafeBufferPointer<Float>) {
        guard let onLevel, !chunk.isEmpty else { return }
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        // Map roughly -50 dB (silence) … -10 dB (loud speech) to 0…1.
        let db = 20 * log10(max(rms, 1e-6))
        let level = min(max((db + 50) / 40, 0), 1)
        DispatchQueue.main.async { onLevel(level) }
    }
}
