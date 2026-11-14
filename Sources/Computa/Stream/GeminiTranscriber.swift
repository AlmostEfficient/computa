import Foundation
import Security

/// Debug trace to stderr: message types and sizes, never audio.
func trace(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write(Data("[gemini \(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)))] \(message())\n".utf8))
}

enum GeminiCredentials {
    static func key() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.computa.gemini", kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw GeminiError.credentials }
        return key
    }
}
enum GeminiError: LocalizedError {
    case credentials, token(Int), protocolFailure, timeout, closed
    var errorDescription: String? {
        switch self {
        case .credentials: "Gemini key unavailable in Keychain. Run the key import script."
        case .token(let status): "Gemini token request failed (HTTP \(status))."
        case .protocolFailure: "Gemini session failed or returned an unexpected response."
        case .timeout: "Gemini did not finish before the timeout."
        case .closed: "Gemini session closed before use."
        }
    }
}

/// One Live session = one dictation. `connect()` does the slow part (token, TLS, setup) and can run
/// ahead of time; `begin()` marks the start of speech. A warmed session that the server closes
/// reports `state == .dead` so the caller can replace it instead of streaming into a dead socket.
actor GeminiTranscriber: StreamingTranscriber {
    static let tokenEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/auth_tokens")!
    static let socketEndpoint = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained")!
    static let sampleRate = 16_000
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<String, Error>?
    enum State: Sendable { case connecting, ready, dead }
    private(set) var state = State.connecting
    nonisolated let createdAt = Date()

    func connect() async throws {
        do { try await open() } catch { state = .dead; throw error }
    }
    private func open() async throws {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue(try GeminiCredentials.key(), forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The default window to *start* a session with a fresh token is short; this token is used immediately.
        request.httpBody = try JSONSerialization.data(withJSONObject: ["uses": 1])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GeminiError.token(status) }
        struct Token: Decodable { let name: String }
        let token = try JSONDecoder().decode(Token.self, from: data)
        var components = URLComponents(url: Self.socketEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "access_token", value: token.name)]
        let socket = URLSession.shared.webSocketTask(with: URLRequest(url: components.url!))
        self.socket = socket; socket.resume()
        let setupTimeout = Task { try await Task.sleep(for: .seconds(15)); socket.cancel(with: .goingAway, reason: nil) }
        defer { setupTimeout.cancel() }
        try await write(["setup": ["model": "models/gemini-3.5-transcribe-live", "generationConfig": ["responseModalities": ["TEXT"]], "inputAudioTranscription": [:], "realtimeInputConfig": ["automaticActivityDetection": ["disabled": true]]]])
        let setup = try await Self.read(socket)
        trace("setup reply \(Self.describe(setup))")
        guard setup["setupComplete"] != nil else { throw GeminiError.protocolFailure }
        state = .ready
        // Read from the start so a server close or goAway while idle marks the session dead.
        reader = Task {
            do {
                var transcript = ""
                while !Task.isCancelled {
                    let message = try await Self.read(socket)
                    trace("recv \(Self.describe(message))")
                    if message["error"] != nil || message["goAway"] != nil { throw GeminiError.closed }
                    guard let content = message["serverContent"] as? [String: Any] else { continue }
                    if let input = content["inputTranscription"] as? [String: Any], let text = input["text"] as? String { transcript += text }
                    if content["turnComplete"] as? Bool == true || content["generationComplete"] as? Bool == true { return transcript }
                }
                throw CancellationError()
            } catch { trace("reader ended: \(error)"); self.markDead(); throw error }
        }
    }
    private func markDead() { state = .dead }
    func begin() async throws {
        trace("begin (state \(state))")
        guard state == .ready else { throw GeminiError.closed }
        try await write(["realtimeInput": ["activityStart": [:]]])
    }
    private static func describe(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object), var text = String(data: data, encoding: .utf8) else { return "?" }
        if text.count > 400 { text = String(text.prefix(400)) + "…" }
        return text
    }
    private static func read(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let data: Data
        switch try await socket.receive() {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw GeminiError.protocolFailure
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GeminiError.protocolFailure }
        return object
    }
    private func write(_ object: [String: Any]) async throws {
        guard let socket else { throw GeminiError.protocolFailure }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    func send(pcm: Data) async throws {
        guard !pcm.isEmpty else { return }
        try await write(["realtimeInput": ["audio": ["data": pcm.base64EncodedString(), "mimeType": "audio/pcm;rate=\(Self.sampleRate)"]]])
    }
    func finish() async throws -> Final {
        guard let socket, let reader else { throw GeminiError.protocolFailure }
        let timeout = Task { try await Task.sleep(for: .seconds(10)); socket.cancel(with: .goingAway, reason: nil) }
        defer { timeout.cancel(); socket.cancel(with: .normalClosure, reason: nil); state = .dead }
        trace("activityEnd sent")
        try await write(["realtimeInput": ["activityEnd": [:]]])
        return Final(text: try await reader.value)
    }
    func cancel() { reader?.cancel(); socket?.cancel(with: .goingAway, reason: nil); reader = nil; socket = nil; state = .dead }
}

/// Keeps one connected session ready so a keypress never waits for token + TLS + setup.
/// The idle session is replaced before the server's 60 s idle cutoff, after wake, and when it dies.
@MainActor final class GeminiWarmPool {
    private var next: (session: GeminiTranscriber, ready: Task<Void, Error>)?
    private var refresher: Task<Void, Never>?
    /// Google closes an idle Live session 60 s after setup (measured 2026-11-14: "Socket is not connected"
    /// at +60.0 s every time), so the idle session is replaced well before that.
    static let maxAge: TimeInterval = 45

    func start() {
        warm()
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await self?.refreshIfNeeded()
            }
        }
    }
    func warm() {
        if let old = next { Task { await old.session.cancel() } }
        let session = GeminiTranscriber()
        next = (session, Task { try await session.connect() })
    }
    private func refreshIfNeeded() async {
        guard let next else { return warm() }
        let state = await next.session.state
        if state == .dead || Date().timeIntervalSince(next.session.createdAt) > Self.maxAge { warm() }
    }
    /// Hands out the idle session (still connecting is fine: audio queues behind `ready`) and warms a replacement.
    /// `wasWarm` reports whether it was already connected at the keypress.
    func take() async -> (session: GeminiTranscriber, ready: Task<Void, Error>, wasWarm: Bool) {
        if next == nil { warm() }
        if await next!.session.state == .dead { warm() }
        let current = next!
        let wasWarm = await current.session.state == .ready
        next = nil
        warm()
        return (current.session, current.ready, wasWarm)
    }
}
