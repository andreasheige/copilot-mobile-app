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
        ZStack {
            CopilotTheme.background.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(CopilotTheme.accent.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(CopilotTheme.accent)
                    }
                    VStack(spacing: 6) {
                        Text("GitHub Copilot")
                            .font(.title2.bold())
                            .foregroundStyle(CopilotTheme.textPrimary)
                        Text("Ask me anything — I can run commands,\nedit files, and more on your Mac.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(CopilotTheme.textSecondary)
                    }
                }
                if ws.isConnected {
                    Button(action: { agentManager.newSession() }) {
                        Label("New Chat", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 13)
                            .background(CopilotTheme.accent)
                            .clipShape(Capsule())
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75).tint(CopilotTheme.textSecondary)
                        Text("Connecting…")
                            .font(.subheadline)
                            .foregroundStyle(CopilotTheme.textSecondary)
                    }
                }
                Spacer()
            }
            .padding()
        }
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
                    .id(session.id)
            } else {
                ZStack {
                    CopilotTheme.background.ignoresSafeArea()
                    VStack(spacing: 28) {
                        Spacer()
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(CopilotTheme.accent.opacity(0.15))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(CopilotTheme.accent)
                            }
                            VStack(spacing: 6) {
                                Text("Terminal")
                                    .font(.title2.bold())
                                    .foregroundStyle(CopilotTheme.textPrimary)
                                Text("Direct shell access to your Mac.")
                                    .font(.subheadline)
                                    .foregroundStyle(CopilotTheme.textSecondary)
                            }
                        }
                        if ws.isConnected {
                            Button(action: { terminalManager.newSession() }) {
                                Label("New Session", systemImage: "plus")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 13)
                                    .background(CopilotTheme.accent)
                                    .clipShape(Capsule())
                            }
                        } else {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.75).tint(CopilotTheme.textSecondary)
                                Text("Connecting…")
                                    .font(.subheadline)
                                    .foregroundStyle(CopilotTheme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }
}
