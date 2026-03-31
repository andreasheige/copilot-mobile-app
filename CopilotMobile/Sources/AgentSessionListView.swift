import SwiftUI

struct AgentSessionListView: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var agentManager: AgentSessionManager
    @EnvironmentObject var ws: TerminalWebSocketManager

    var body: some View {
        List(selection: Binding(
            get: { agentManager.activeSessionId },
            set: { agentManager.activeSessionId = $0 }
        )) {
            ForEach(agentManager.sessions) { session in
                NavigationLink(value: session.id) {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(CopilotTheme.accent)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if let last = session.messages.last {
                                Text(last.content.isEmpty ? "…" : last.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in
                offsets.map { agentManager.sessions[$0].id }.forEach { agentManager.deleteSession($0) }
            }
        }
        .navigationTitle("Copilot")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gear") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    connectionIndicator
                    Button { agentManager.newSession() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(!ws.isConnected)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        ZStack {
            Circle()
                .fill(ws.isConnected ? CopilotTheme.success.opacity(0.25) : CopilotTheme.danger.opacity(0.25))
                .frame(width: 14, height: 14)
            Circle()
                .fill(ws.isConnected ? CopilotTheme.success : CopilotTheme.danger)
                .frame(width: 8, height: 8)
        }
    }
}
