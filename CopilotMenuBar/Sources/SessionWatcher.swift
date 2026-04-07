import Foundation
import AppKit

@MainActor
final class SessionWatcher: ObservableObject {
    @Published var terminalSessions: [MBTerminalSession] = []
    @Published var agentSessions: [MBAgentSession] = []
    @Published var isConnected = false

    private var ws: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    init() { connect() }

    // MARK: - Connection

    func connect() {
        let apiKey = readAPIKey()
        guard !apiKey.isEmpty,
              let url = URL(string: "ws://localhost:3003") else { return }
        ws?.cancel()
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        ws = task
        isConnected = true
        listen()
        startPing()
    }

    private func listen() {
        ws?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handle(msg)
                    self.listen()
                case .failure:
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8)
        @unknown default:    text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(WSMessage.self, from: data)
        else { return }
        process(msg)
    }

    private func process(_ msg: WSMessage) {
        switch msg.type {
        case "screen", "status":
            guard let sid = msg.sessionId else { return }
            if let idx = terminalSessions.firstIndex(where: { $0.id == sid }) {
                if let s = msg.status {
                    terminalSessions[idx].status = SessionStatus(rawValue: s) ?? .idle
                }
                terminalSessions[idx].lastActivityAt = Date()
            } else {
                var s = MBTerminalSession(id: sid)
                if let st = msg.status { s.status = SessionStatus(rawValue: st) ?? .idle }
                terminalSessions.insert(s, at: 0)
            }

        case "session_created":
            guard let sid = msg.sessionId else { return }
            if !terminalSessions.contains(where: { $0.id == sid }) {
                terminalSessions.insert(MBTerminalSession(id: sid), at: 0)
            }

        case "agent_session_created":
            guard let sid = msg.sessionId else { return }
            if !agentSessions.contains(where: { $0.id == sid }) {
                agentSessions.insert(MBAgentSession(id: sid), at: 0)
            }

        case "agent_done":
            guard let sid = msg.sessionId,
                  let idx = agentSessions.firstIndex(where: { $0.id == sid }) else { return }
            agentSessions[idx].lastMessageAt = Date()
            agentSessions[idx].status = .idle
            agentSessions[idx].currentTool = nil

        case "agent_status":
            guard let sid = msg.sessionId else { return }
            if let idx = agentSessions.firstIndex(where: { $0.id == sid }) {
                switch msg.status {
                case "thinking":
                    agentSessions[idx].status = .thinking
                    agentSessions[idx].startedAt = Date()
                case "running_tool":
                    let toolName = msg.tool ?? "tool"
                    agentSessions[idx].status = .runningTool(name: toolName)
                    agentSessions[idx].currentTool = toolName
                case "idle":
                    agentSessions[idx].status = .idle
                    agentSessions[idx].currentTool = nil
                default: break
                }
            } else if msg.status == "thinking" || msg.status == "running_tool" {
                var s = MBAgentSession(id: sid)
                s.status = msg.status == "thinking" ? .thinking : .runningTool(name: msg.tool ?? "tool")
                agentSessions.insert(s, at: 0)
            }

        case "tool_start":
            guard let sid = msg.sessionId, let tool = msg.tool,
                  let idx = agentSessions.firstIndex(where: { $0.id == sid }) else { return }
            agentSessions[idx].status = .runningTool(name: tool)
            agentSessions[idx].currentTool = tool

        case "tool_complete":
            guard let sid = msg.sessionId,
                  let idx = agentSessions.firstIndex(where: { $0.id == sid }) else { return }
            agentSessions[idx].status = .thinking
            agentSessions[idx].currentTool = nil

        default: break
        }
    }

    // MARK: - Actions

    func openInTerminal(_ session: MBTerminalSession) {
        let script = "/tmp/copilot-menu-attach.sh"
        let content = "#!/bin/bash\nexec /opt/homebrew/bin/tmux select-window -t 'copilot-mobile:\(session.id)' && exec /opt/homebrew/bin/tmux attach -t copilot-mobile\n"
        try? content.write(toFile: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        NSWorkspace.shared.open(URL(fileURLWithPath: script))
    }

    func newSession() {
        let apiKey = readAPIKey()
        guard let url = URL(string: "http://localhost:3003/health") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        // Just trigger the new session sheet on the iOS app — or open terminal directly
        let name = "session-\(Int(Date().timeIntervalSince1970) % 10000)"
        let msg = WSMessage(type: "new_session", sessionId: name, cols: 220, rows: 50, tmuxSession: name)
        sendMessage(msg)
    }

    private func sendMessage(_ msg: WSMessage) {
        guard let data = try? JSONEncoder().encode(msg),
              let text = String(data: data, encoding: .utf8) else { return }
        ws?.send(.string(text)) { _ in }
    }

    // MARK: - API Key

    private func readAPIKey() -> String {
        // Try reading from server .env first (same machine)
        let envPaths = [
            NSHomeDirectory() + "/Work/app-test/server/.env",
            NSHomeDirectory() + "/app-test/server/.env",
        ]
        for path in envPaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    if line.hasPrefix("API_KEY=") {
                        return String(line.dropFirst("API_KEY=".count)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        // Fall back to UserDefaults
        return UserDefaults.standard.string(forKey: "apiKey") ?? ""
    }

    // MARK: - Ping / Reconnect

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { sendMessage(WSMessage(type: "ping")) }
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { connect() }
        }
    }
}
