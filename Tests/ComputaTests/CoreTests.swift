import Testing
import Foundation
import CaptureRing
@testable import Computa
@Test func ringPreservesOrderAndReportsOverflow() {
    let ring = ring_create(4)!
    defer { ring_destroy(ring) }
    let input: [Float] = [1,2,3,4,5]
    #expect(ring_write(ring, input, 5, 42) == 4)
    #expect(ring_dropped(ring) == 1)
    var output = [Float](repeating: 0, count: 3)
    #expect(ring_read(ring, &output, 3) == 3)
    #expect(output == [1,2,3])
    #expect(ring_write(ring, input, 3, 50) == 3)
    var wrapped = [Float](repeating: 0, count: 4)
    #expect(ring_read(ring, &wrapped, 4) == 4)
    #expect(wrapped == [4,1,2,3])
    #expect(ring_first_host(ring) == 42)
    ring_reset(ring)
    #expect(ring_first_host(ring) == 0)
}
@Test func distribution() {
    #expect(Statistics.percentile([], 0.5) == nil)
    #expect(Statistics.percentile(Array(1...20).map(Double.init), 0.9) == 19)
}
@Test func resamplerConverts48kTo16kPCM16() {
    let resampler = Resampler(inputRate: 48_000)!
    // 1 s of a 440 Hz sine at half scale, fed in 20 ms chunks like the drain loop.
    let sine = (0..<48_000).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
    var out = Data()
    for start in stride(from: 0, to: sine.count, by: 960) { out.append(resampler.convert(Array(sine[start..<min(start + 960, sine.count)]))) }
    out.append(resampler.flush())
    let samples = out.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    #expect(abs(samples.count - 16_000) <= 64)
    let peak = samples.map { abs(Int($0)) }.max() ?? 0
    #expect(peak > 15_000 && peak < 18_000)   // ≈ 0.5 × 32767
}
@Test func vocabularyReplacesMishearingsAndFixesCase() {
    let entries = VocabularyEntry.parse("Computa: computer\nGhostty: Ghosty, ghost tea, Ghostwriter\n\nAPI")
    #expect(entries.count == 3)
    #expect(VocabularyEntry.apply(entries, to: "Open computer and start dictating into Ghosty.") == "Open Computa and start dictating into Ghostty.")
    #expect(VocabularyEntry.apply(entries, to: "use the api in ghost tea") == "use the API in Ghostty")
    // Whole words only: no replacement inside other words.
    #expect(VocabularyEntry.apply(entries, to: "computers and Ghostwriters") == "computers and Ghostwriters")
}
