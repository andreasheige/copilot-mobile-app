import SwiftUI

struct SessionListView: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var ws: TerminalWebSocketManager
    @EnvironmentObject var sessionManager: TerminalSessionManager

    var body: some View {
        List(selection: Binding(
            get: { sessionManager.activeSessionId },
            set: { sessionManager.activeSessionId = $0 }
        )) {
            ForEach(sessionManager.sessions) { session in
                NavigationLink(value: session.id) {
                    Label(
                        "Session \(session.createdAt.formatted(.dateTime.hour().minute().second()))",
                        systemImage: "terminal"
                    )
                }
            }
            .onDelete { offsets in
                offsets.map { sessionManager.sessions[$0].id }.forEach { sessionManager.closeSession($0) }
            }
        }
        .navigationTitle("Terminal")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gear") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    Circle().fill(ws.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
                    Button { sessionManager.newSession() } label: { Image(systemName: "plus") }
                        .disabled(!ws.isConnected)
                }
            }
        }
    }
}
