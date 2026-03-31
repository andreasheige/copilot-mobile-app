import Foundation

@MainActor
final class TerminalSessionManager: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionId: String?

    private let ws: TerminalWebSocketManager

    init(ws: TerminalWebSocketManager) {
        self.ws = ws
    }

    func newSession(cols: Int = 220, rows: Int = 50) {
        let name = "mobile"
        if sessions.first(where: { $0.id == name }) == nil {
            sessions.insert(TerminalSession(id: name), at: 0)
        }
        activeSessionId = name
        ws.send(WSMessage(type: "new_session", sessionId: name, cols: cols, rows: rows))
    }

    func sendInput(_ text: String, to sessionId: String) {
        ws.send(WSMessage(type: "input", sessionId: sessionId, data: text))
    }

    func closeSession(_ id: String) {
        ws.send(WSMessage(type: "close_session", sessionId: id))
        sessions.removeAll { $0.id == id }
        if activeSessionId == id { activeSessionId = sessions.first?.id }
    }

    var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case "output", "screen":
            guard let sid = msg.sessionId, let data = msg.data,
                  let idx = sessions.firstIndex(where: { $0.id == sid }) else { return }
            if msg.type == "screen" {
                sessions[idx].output = Self.stripANSI(data)
            } else {
                sessions[idx].output += Self.stripANSI(data)
            }
        case "session_ended":
            guard let sid = msg.sessionId,
                  let idx = sessions.firstIndex(where: { $0.id == sid }) else { return }
            sessions[idx].output += "\n\n[Session ended]"
        case "error":
            if let sid = msg.sessionId,
               let idx = sessions.firstIndex(where: { $0.id == sid }) {
                sessions[idx].output += "\n⚠️ \(msg.message ?? "Error")"
            }
        default: break
        }
    }

    private static let ansiPattern = try! NSRegularExpression(
        pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)"#
    )
    private static func stripANSI(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return ansiPattern.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }
}
