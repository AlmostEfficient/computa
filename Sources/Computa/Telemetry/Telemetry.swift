import Foundation
import os
/// One dictation. All `*MS` intervals start at the key event as seen by the tap callback
/// (or the button/self-test call when `source` is not "key"). None of them is acoustic onset.
struct Trial: Codable {
    var source: String
    let condition: String
    let sampleRate: Double
    /// Event timestamp → tap callback.
    let eventToTapMS: Double?
    /// Key → `engine.start()` returned.
    let startReturnMS: Double
    /// Key → host time of the first captured sample.
    let firstCallbackMS: Double?
    let droppedFrames: UInt64
    var warmSession: Bool?
    var fallback: Bool?
    /// Key release → final text available (before insertion).
    var releaseToTextMS: Double?
}
enum Statistics {
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[Int((Double(sorted.count - 1) * p).rounded(.up))]
    }
}
@MainActor final class Telemetry {
    let signposter = OSSignposter(subsystem: "dev.computa.app", category: "Capture")
    let url: URL
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Computa")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("capture.jsonl")
    }
    func record(_ trial: Trial) throws {
        var data = try JSONEncoder().encode(trial); data.append(10)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
}
