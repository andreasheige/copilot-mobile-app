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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.headline).lineLimit(1)
                        if let last = session.messages.last {
                            Text(last.content.isEmpty ? "…" : last.content)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                    Circle().fill(ws.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
                    Button { agentManager.newSession() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(!ws.isConnected)
                }
            }
        }
    }
}
