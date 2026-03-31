import Foundation

// MARK: - Shared

struct WSMessage: Codable {
    var type: String
    var sessionId: String?
    var data: String?
    var message: String?
    var content: String?
    var tool: String?
    var args: [String: AnyCodable]?
    var hint: String?
    var status: String?
    var cols: Int?
    var rows: Int?
    var workDir: String?
    var tmuxSession: String?
    var startCommand: String?
    var preferredTerminal: String?
}

// MARK: - Terminal

enum SessionStatus: String {
    case running, idle, stale, ended
    var color: String {
        switch self {
        case .running: return "green"
        case .idle: return "yellow"
        case .stale: return "orange"
        case .ended: return "red"
        }
    }
    var label: String {
        switch self {
        case .running: return "Running"
        case .idle: return "Idle"
        case .stale: return "Stale"
        case .ended: return "Ended"
        }
    }
}

struct TerminalSession: Identifiable {
    let id: String
    var workDir: String = ""
    var output: String = ""
    var status: SessionStatus = .idle
    var lastActivityAt: Date = Date()
    let createdAt: Date = Date()
}

// MARK: - Agent

struct AgentMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var toolCalls: [ToolCall]
    var isStreaming: Bool
    let timestamp: Date

    enum Role: Codable { case user, assistant }

    struct ToolCall: Identifiable, Codable {
        let id: UUID
        let tool: String
        var args: String
        init(tool: String, args: String) {
            self.id = UUID(); self.tool = tool; self.args = args
        }
    }

    init(id: UUID = UUID(), role: Role, content: String = "",
         toolCalls: [ToolCall] = [], isStreaming: Bool = false,
         timestamp: Date = Date()) {
        self.id = id; self.role = role; self.content = content
        self.toolCalls = toolCalls; self.isStreaming = isStreaming
        self.timestamp = timestamp
    }
}

struct AgentSession: Identifiable, Codable {
    let id: String
    var title: String = "New Chat"
    var messages: [AgentMessage] = []
    let createdAt: Date = Date()
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? String { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
        else { try container.encode("") }
    }
}
