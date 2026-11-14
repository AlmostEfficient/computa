@preconcurrency import AVFoundation
import CoreAudio
import CaptureRing

// Pointer lifetime exceeds the sink callback; reset is only permitted while paused.
final class SampleQueue: @unchecked Sendable {
    let pointer: OpaquePointer
    init() { pointer = ring_create(192_000 * 30)! }
    deinit { ring_destroy(pointer) }
}

/// Converts native-rate mono Float32 to 16 kHz mono PCM16 off the real-time thread.
/// Streaming: call `convert` per chunk, then `flush` once at the end of a session.
final class Resampler {
    static let outputRate = 16_000.0
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let converter: AVAudioConverter
    init?(inputRate: Double) {
        guard let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate, channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.outputRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        self.input = input; self.output = output; self.converter = converter
    }
    func reset() { converter.reset() }
    func convert(_ samples: [Float]) -> Data { run(samples, end: false) }
    func flush() -> Data { run([], end: true) }
    private func run(_ samples: [Float], end: Bool) -> Data {
        nonisolated(unsafe) var pending: AVAudioPCMBuffer?  // the input block runs synchronously inside convert()
        if !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count)) {
            buffer.frameLength = buffer.frameCapacity
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            pending = buffer
        }
        let capacity = AVAudioFrameCount(Double(samples.count) * Self.outputRate / input.sampleRate) + 1024
        var result = Data()
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { break }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, state in
                if let buffer = pending { pending = nil; state.pointee = .haveData; return buffer }
                state.pointee = end ? .endOfStream : .noDataNow
                return nil
            }
            if out.frameLength > 0 { result.append(Data(bytes: out.int16ChannelData![0], count: Int(out.frameLength) * 2)) }
            if status != .haveData || error != nil { break }
        }
        return result
    }
}

@MainActor final class AudioCapture {
    private let engine = AVAudioEngine()
    private let queue = SampleQueue()
    private var sink: AVAudioSinkNode?
    private var resampler: Resampler?
    private(set) var sampleRate = 0.0
    var firstHost: UInt64 { ring_first_host(queue.pointer) }
    var dropped: UInt64 { ring_dropped(queue.pointer) }
    var prepared: Bool { sink != nil }
    func prepare() throws {
        guard sink == nil else { return }
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { throw CaptureError.unsupportedFormat }
        var transport: UInt32 = 0
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { throw CaptureError.unsupportedFormat }
        guard transport != kAudioDeviceTransportTypeBluetooth, transport != kAudioDeviceTransportTypeBluetoothLE else { throw CaptureError.bluetoothInput }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw CaptureError.unsupportedFormat
        }
        guard let resampler = Resampler(inputRate: format.sampleRate) else { throw CaptureError.unsupportedFormat }
        sampleRate = format.sampleRate
        let node = Self.makeSink(queue)
        engine.attach(node)
        engine.connect(input, to: node, format: format)
        engine.prepare()
        self.resampler = resampler
        sink = node
    }
    /// Must stay nonisolated: a closure formed inside a @MainActor method inherits main-actor
    /// isolation, and Swift 6 traps when CoreAudio invokes it on the real-time I/O thread.
    private nonisolated static func makeSink(_ queue: SampleQueue) -> AVAudioSinkNode {
        AVAudioSinkNode { timestamp, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
            if let data = list.first?.mData {
                _ = ring_write(queue.pointer, data.assumingMemoryBound(to: Float.self), Int(frames), timestamp.pointee.mHostTime)
            }
            return noErr
        }
    }
    func start() throws { ring_reset(queue.pointer); resampler?.reset(); try engine.start() }
    func pause() { engine.pause() }
    /// Drains everything captured so far as 16 kHz PCM16. `final` flushes the converter's tail.
    /// Input level of the most recent drain, 0…1 (−55 dBFS → 0, −10 dBFS → 1). For the on-screen meter.
    private(set) var level: Float = 0
    func drainPCM16(final: Bool = false) -> Data {
        var out = Data()
        var samples = [Float](repeating: 0, count: 8192)
        var energy: Float = 0, total = 0
        while true {
            let count = ring_read(queue.pointer, &samples, samples.count)
            if count == 0 { break }
            for i in 0..<count { energy += samples[i] * samples[i] }
            total += count
            out.append(resampler?.convert(Array(samples.prefix(count))) ?? Data())
        }
        if total > 0 {
            let db = 20 * log10(max(sqrt(energy / Float(total)), 1e-6))
            level = min(max((db + 55) / 45, 0), 1)
        }
        if final { out.append(resampler?.flush() ?? Data()) }
        return out
    }
    enum CaptureError: Error { case unsupportedFormat, bluetoothInput }
}
