import Foundation
let path = CommandLine.arguments.dropFirst().first ?? NSHomeDirectory() + "/Library/Application Support/Computa/capture.jsonl"
let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
let records = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
let groups = Dictionary(grouping: records) { "\($0["source"] as? String ?? "legacy")/\($0["condition"] as? String ?? "?")" + (($0["warmSession"] as? Bool).map { $0 ? "/warm" : "/cold-socket" } ?? "") }
for name in groups.keys.sorted() {
    let group = groups[name]!
    print("\(name): \(group.count) trials\(group.count < 20 ? " — insufficient trials" : "")")
    for key in ["eventToTapMS", "startReturnMS", "firstCallbackMS", "releaseToTextMS"] {
        let values = group.compactMap { $0[key] as? Double }.sorted()
        guard !values.isEmpty else { continue }
        print(key, zip(["p50", "p90", "p99"], [0.5, 0.9, 0.99]).map { name, p in "\(name)=\(String(format: "%.2f", values[Int((Double(values.count - 1) * p).rounded(.up))]))ms" }.joined(separator: " "))
    }
}
print("Intervals start at the key tap callback (source=key) or the call itself (selftest/manual). firstCallbackMS is the first captured sample, not acoustic onset.")
