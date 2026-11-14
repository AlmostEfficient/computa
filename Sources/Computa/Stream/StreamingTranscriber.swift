import Foundation
struct Final: Sendable { let text: String }
protocol StreamingTranscriber: Sendable {
    func connect() async throws
    func send(pcm: Data) async throws
    func finish() async throws -> Final
    func cancel() async
}
// The endpoint must return {"token":"short-lived-provider-token"} over HTTPS.
// Provider keys are never stored in the application.
actor DeepgramTranscriber: StreamingTranscriber {
    let tokenURL: URL
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<String, Error>?
    private let rate: Double
    init(tokenURL: URL, sampleRate: Double) { self.tokenURL = tokenURL; rate = sampleRate }
    func connect() async throws {
        guard tokenURL.scheme == "https" else { throw URLError(.secureConnectionFailed) }
        let (data, response) = try await URLSession.shared.data(from: tokenURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
        struct Token: Decodable { let token: String }
        let token = try JSONDecoder().decode(Token.self, from: data).token
        let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&encoding=linear16&sample_rate=\(Int(rate))&channels=1&smart_format=true&interim_results=true")!
        var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request); socket = task; task.resume()
        reader = Task {
            var segments: [String] = []
            while !Task.isCancelled {
                let message = try await task.receive()
                let data: Data
                switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if object["type"] as? String == "Metadata" { return segments.joined(separator: " ") }
                if object["type"] as? String == "Error" { throw URLError(.badServerResponse) }
                if object["is_final"] as? Bool == true,
                   let channel = object["channel"] as? [String: Any],
                   let alternatives = channel["alternatives"] as? [[String: Any]],
                   let transcript = alternatives.first?["transcript"] as? String, !transcript.isEmpty { segments.append(transcript) }
            }
            throw CancellationError()
        }
    }
    func send(pcm: Data) async throws {
        guard let socket else { throw URLError(.notConnectedToInternet) }
        try await socket.send(.data(pcm))
    }
    func finish() async throws -> Final {
        guard let socket, let reader else { throw URLError(.notConnectedToInternet) }
        try await socket.send(.string("{\"type\":\"CloseStream\"}"))
        let timeout = Task { try await Task.sleep(for: .seconds(8)); socket.cancel(with: .goingAway, reason: nil) }
        defer { timeout.cancel(); socket.cancel(with: .normalClosure, reason: nil) }
        return Final(text: try await reader.value)
    }
    func cancel() { reader?.cancel(); socket?.cancel(with: .goingAway, reason: nil); reader = nil; socket = nil }
}
