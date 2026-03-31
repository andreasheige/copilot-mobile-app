import Foundation

private struct PersistedSession: Codable {
    let id: String
    let workDir: String
    let createdAt: Date
}

private let persistKey = "copilot_terminal_sessions"
private let recentPathsKey = "copilot_recent_paths"
private let placeholderPaths: [(String, String)] = [
    ("Home", "~"),
    ("Desktop", "~/Desktop"),
    ("Documents", "~/Documents"),
    ("Work", "~/Work"),
    ("Downloads", "~/Downloads"),
]

@MainActor
final class TerminalSessionManager: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionId: String?
    @Published var recentPaths: [(label: String, path: String)] = []

    private let ws: TerminalWebSocketManager

    init(ws: TerminalWebSocketManager) {
        self.ws = ws
        loadPersisted()
        loadRecentPaths()
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: persistKey),
              let stored = try? JSONDecoder().decode([PersistedSession].self, from: data)
        else { return }
        sessions = stored.map {
            var s = TerminalSession(id: $0.id)
            s.workDir = $0.workDir
            s.status = .stale
            return s
        }
    }

    private func savePersisted() {
        let stored = sessions.map { PersistedSession(id: $0.id, workDir: $0.workDir, createdAt: $0.createdAt) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: persistKey)
        }
    }

    private func loadRecentPaths() {
        let saved = UserDefaults.standard.stringArray(forKey: recentPathsKey) ?? []
        rebuildRecentPaths(from: saved)
    }

    private func saveRecentPath(_ path: String) {
        guard !path.isEmpty else { return }
        var saved = UserDefaults.standard.stringArray(forKey: recentPathsKey) ?? []
        saved.removeAll { $0 == path }
        saved.insert(path, at: 0)
        if saved.count > 5 { saved = Array(saved.prefix(5)) }
        UserDefaults.standard.set(saved, forKey: recentPathsKey)
        rebuildRecentPaths(from: saved)
    }

    private func rebuildRecentPaths(from saved: [String]) {
        var result: [(label: String, path: String)] = saved.map { (label: $0, path: $0) }
        // Fill remaining slots with placeholders not already in the list
        for placeholder in placeholderPaths where result.count < 5 && !result.contains(where: { $0.path == placeholder.1 }) {
            result.append((label: placeholder.0, path: placeholder.1))
        }
        recentPaths = result
    }

    // MARK: - Re-subscribe on reconnect

    func resubscribeAll() {
        for session in sessions where session.status != .ended {
            ws.send(WSMessage(type: "new_session", sessionId: session.id,
                              cols: 220, rows: 50,
                              workDir: session.workDir.isEmpty ? nil : session.workDir,
                              tmuxSession: session.id))
        }
    }

    // MARK: - Session management

    func newSession(name: String = "mobile", workDir: String = "", startCommand: String = "", preferredTerminal: String? = nil, cols: Int = 220, rows: Int = 50) {
        let resolvedName = name.isEmpty ? "mobile" : name
        if sessions.first(where: { $0.id == resolvedName }) == nil {
            var s = TerminalSession(id: resolvedName)
            s.workDir = workDir
            sessions.insert(s, at: 0)
            savePersisted()
        }
        activeSessionId = resolvedName
        if !workDir.isEmpty { saveRecentPath(workDir) }
        ws.send(WSMessage(
            type: "new_session", sessionId: resolvedName,
            cols: cols, rows: rows,
            workDir: workDir.isEmpty ? nil : workDir,
            tmuxSession: resolvedName,
            startCommand: startCommand.isEmpty ? nil : startCommand,
            preferredTerminal: preferredTerminal
        ))
    }

    func sendInput(_ text: String, to sessionId: String) {
        ws.send(WSMessage(type: "input", sessionId: sessionId, data: text))
    }

    func closeSession(_ id: String) {
        ws.send(WSMessage(type: "close_session", sessionId: id))
        sessions.removeAll { $0.id == id }
        if activeSessionId == id { activeSessionId = sessions.first?.id }
        savePersisted()
    }

    var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - Message handling

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
            sessions[idx].lastActivityAt = Date()
            if let s = msg.status { sessions[idx].status = SessionStatus(rawValue: s) ?? .idle }

        case "status":
            guard let sid = msg.sessionId,
                  let idx = sessions.firstIndex(where: { $0.id == sid }),
                  let s = msg.status else { return }
            sessions[idx].status = SessionStatus(rawValue: s) ?? .idle

        case "session_ended":
            guard let sid = msg.sessionId,
                  let idx = sessions.firstIndex(where: { $0.id == sid }) else { return }
            sessions[idx].output += "\n\n[Session ended]"
            sessions[idx].status = .ended

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
