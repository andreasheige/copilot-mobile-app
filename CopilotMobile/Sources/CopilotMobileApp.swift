import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    let settings = AppSettings()
    let ws: TerminalWebSocketManager
    let terminalManager: TerminalSessionManager
    let agentManager: AgentSessionManager

    init() {
        let ws = TerminalWebSocketManager()
        self.ws = ws
        self.terminalManager = TerminalSessionManager(ws: ws)
        self.agentManager = AgentSessionManager(ws: ws)
        // Route all WS messages to both managers
        ws.onMessage = { [weak self] msg in
            self?.terminalManager.handleMessage(msg)
            self?.agentManager.handleMessage(msg)
        }
    }
}

@main
struct CopilotMobileApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container.settings)
                .environmentObject(container.ws)
                .environmentObject(container.terminalManager)
                .environmentObject(container.agentManager)
        }
    }
}
