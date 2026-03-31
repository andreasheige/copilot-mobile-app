import Foundation

private let agentSessionsKey = "copilot_agent_sessions"

@MainActor
final class AgentSessionManager: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var activeSessionId: String?

    private let ws: TerminalWebSocketManager

    init(ws: TerminalWebSocketManager) {
        self.ws = ws
        loadPersisted()
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: agentSessionsKey),
              let stored = try? JSONDecoder().decode([AgentSession].self, from: data)
        else { return }
        // Mark any in-progress messages as done
        sessions = stored.map { session in
            var s = session
            s.messages = s.messages.map { msg in
                var m = msg; m.isStreaming = false; return m
            }
            return s
        }
    }

    private func savePersisted() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: agentSessionsKey)
        }
    }

    // MARK: - Message handling

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case "agent_chunk":
            guard let sid = msg.sessionId, let chunk = msg.content,
                  let idx = sessions.firstIndex(where: { $0.id == sid }) else { return }
            if let lastIdx = sessions[idx].messages.indices.last,
               sessions[idx].messages[lastIdx].role == .assistant,
               sessions[idx].messages[lastIdx].isStreaming {
                sessions[idx].messages[lastIdx].content += chunk
            } else {
                sessions[idx].messages.append(AgentMessage(role: .assistant, content: chunk, isStreaming: true))
            }

        case "agent_done":
            guard let sid = msg.sessionId,
                  let idx = sessions.firstIndex(where: { $0.id == sid }) else { return }
            if let lastIdx = sessions[idx].messages.indices.last {
                sessions[idx].messages[lastIdx].isStreaming = false
            }
            updateTitle(at: idx)
            savePersisted()

        case "agent_error":
            guard let sid = msg.sessionId,
                  let idx = sessions.firstIndex(where: { $0.id == sid }) else { return }
            let errMsg = AgentMessage(role: .assistant, content: "⚠️ \(msg.message ?? "Error")")
            sessions[idx].messages.append(errMsg)
            savePersisted()

        case "tool_call":
            guard let sid = msg.sessionId,
                  let idx = sessions.firstIndex(where: { $0.id == sid }),
                  let tool = msg.tool else { return }
            let toolCall = AgentMessage.ToolCall(tool: tool, args: "")
            if let lastIdx = sessions[idx].messages.indices.last,
               sessions[idx].messages[lastIdx].role == .assistant,
               sessions[idx].messages[lastIdx].isStreaming {
                sessions[idx].messages[lastIdx].toolCalls.append(toolCall)
            } else {
                var m = AgentMessage(role: .assistant, isStreaming: true)
                m.toolCalls.append(toolCall)
                sessions[idx].messages.append(m)
            }

        case "agent_session_created":
            break

        default: break
        }
    }

    // MARK: - Session management

    func newSession() -> String {
        let sessionId = UUID().uuidString
        sessions.insert(AgentSession(id: sessionId), at: 0)
        activeSessionId = sessionId
        ws.send(WSMessage(type: "new_agent_session", sessionId: sessionId))
        savePersisted()
        return sessionId
    }

    func sendMessage(_ content: String, in sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages.append(AgentMessage(role: .user, content: content))
        ws.send(WSMessage(type: "agent_chat", sessionId: sessionId, content: content))
        savePersisted()
    }

    func deleteSession(_ id: String) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id { activeSessionId = sessions.first?.id }
        savePersisted()
    }

    var activeSession: AgentSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    var isResponding: Bool {
        activeSession?.messages.last?.isStreaming ?? false
    }

    private func updateTitle(at idx: Int) {
        guard sessions[idx].title == "New Chat",
              let first = sessions[idx].messages.first(where: { $0.role == .user }) else { return }
        let words = first.content.split(separator: " ").prefix(5).joined(separator: " ")
        sessions[idx].title = words.isEmpty ? "Chat" : words
    }
}
