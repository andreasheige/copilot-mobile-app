import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ws: TerminalWebSocketManager
    @State private var showSettings = false

    var body: some View {
        Group {
            if !settings.isConfigured || showSettings {
                SettingsView(isPresented: $showSettings)
            } else {
                MainTabView(showSettings: $showSettings)
            }
        }
        .onAppear {
            if settings.isConfigured, let url = settings.wsURL {
                ws.connect(to: url)
            }
        }
    }
}

struct MainTabView: View {
    @Binding var showSettings: Bool

    var body: some View {
        TabView {
            AgentTab(showSettings: $showSettings)
                .tabItem {
                    Label("Copilot", systemImage: "bubble.left.and.bubble.right.fill")
                }

            TerminalTab(showSettings: $showSettings)
                .tabItem {
                    Label("Terminal", systemImage: "terminal.fill")
                }
        }
    }
}

// MARK: - Agent Tab

struct AgentTab: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var agentManager: AgentSessionManager
    @EnvironmentObject var ws: TerminalWebSocketManager

    var body: some View {
        NavigationSplitView {
            AgentSessionListView(showSettings: $showSettings)
        } detail: {
            if let session = agentManager.activeSession {
                AgentChatView(sessionId: session.id)
            } else {
                agentWelcome
            }
        }
    }

    private var agentWelcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Copilot CLI").font(.title.bold())
            Text("Ask me anything — I can run commands,\nedit files, and more on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if ws.isConnected {
                Button("New Chat") { agentManager.newSession() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Label("Connecting…", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Terminal Tab

struct TerminalTab: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var terminalManager: TerminalSessionManager
    @EnvironmentObject var ws: TerminalWebSocketManager

    var body: some View {
        NavigationSplitView {
            SessionListView(showSettings: $showSettings)
        } detail: {
            if let session = terminalManager.activeSession {
                TerminalView(sessionId: session.id)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                    Text("Terminal").font(.title.bold())
                    Text("Direct shell access to your Mac.\nOn your Mac: tmux attach -t mobile")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if ws.isConnected {
                        Button("New Session") { terminalManager.newSession() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Label("Connecting…", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
    }
}
