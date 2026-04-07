import Foundation
import SwiftUI

// Shared with iOS app — same message format
struct WSMessage: Codable {
    var type: String
    var sessionId: String?
    var data: String?
    var message: String?
    var content: String?
    var tool: String?
    var hint: String?
    var status: String?
    var cols: Int?
    var rows: Int?
    var workDir: String?
    var tmuxSession: String?
    var startCommand: String?
    var preferredTerminal: String?
}

enum SessionStatus: String {
    case running, idle, stale, ended
    var label: String {
        switch self {
        case .running: return "Running"
        case .idle:    return "Idle"
        case .stale:   return "Stale"
        case .ended:   return "Ended"
        }
    }
}

struct MBTerminalSession: Identifiable {
    let id: String
    var workDir: String = ""
    var status: SessionStatus = .idle
    var lastActivityAt: Date = Date()
}

enum AgentStatus {
    case idle, thinking, runningTool(name: String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking…"
        case .runningTool(let name): return "Running \(name)"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .thinking: return .blue
        case .runningTool: return .orange
        }
    }

    var icon: String {
        switch self {
        case .idle: return "bubble.left.and.bubble.right"
        case .thinking: return "ellipsis.bubble"
        case .runningTool: return "wrench.and.screwdriver"
        }
    }
}

struct MBAgentSession: Identifiable {
    let id: String
    var title: String = "New Chat"
    var status: AgentStatus = .idle
    var currentTool: String? = nil
    var messageCount: Int = 0
    var lastMessageAt: Date = Date()
    var startedAt: Date? = nil
}
