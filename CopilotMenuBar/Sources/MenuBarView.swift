import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var watcher: SessionWatcher
    @EnvironmentObject var localWatcher: LocalProcessWatcher

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    localTmuxSection
                    if !watcher.agentSessions.isEmpty {
                        Divider().padding(.horizontal, 12)
                        agentSection
                    }
                    if !localWatcher.aiProcesses.isEmpty {
                        Divider().padding(.horizontal, 12)
                        localAISection
                    }
                }
            }
            .frame(maxHeight: 400)
            Divider()
            footer
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.blue)
            Text("Copilot Sessions")
                .font(.headline)
            Spacer()
            let localCount = localWatcher.tmuxWindows.count
            let activeAgents = watcher.agentSessions.filter {
                if case .idle = $0.status { return false }
                return true
            }.count
            let totalActive = localCount + activeAgents
            if totalActive > 0 {
                Text("\(totalActive)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            Circle()
                .fill(watcher.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Local tmux windows (all, no server needed)

    private var localTmuxSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("TERMINALS (LOCAL)")
            if localWatcher.tmuxWindows.isEmpty {
                Text("No tmux windows found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(localWatcher.tmuxWindows) { win in
                    TmuxWindowRow(window: win)
                }
            }
        }
    }

    // MARK: - Terminal sessions (server-managed, kept for reference)

    // MARK: - Agent sessions

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("COPILOT CHATS")
            ForEach(watcher.agentSessions) { session in
                AgentRow(session: session)
            }
        }
    }

    private var localAISection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("LOCALLY RUNNING")
            ForEach(localWatcher.aiProcesses) { process in
                LocalAIRow(process: process)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                watcher.newSession()
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .disabled(!watcher.isConnected)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Terminal Row

private struct TerminalRow: View {
    let session: MBTerminalSession

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle:    return .yellow
        case .stale:   return .orange
        case .ended:   return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(statusColor.opacity(0.2)).frame(width: 12, height: 12)
                Circle().fill(statusColor).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.id)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if !session.workDir.isEmpty {
                    Text(session.workDir)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(session.status.label)
                .font(.caption2)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(Color.primary.opacity(0.001)) // makes full row tappable
        .hoverEffect()
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let session: MBAgentSession

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if case .thinking = session.status {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 12, height: 12)
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                } else if case .runningTool = session.status {
                    Circle().fill(Color.orange.opacity(0.2)).frame(width: 12, height: 12)
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                } else {
                    Circle().fill(Color.secondary.opacity(0.2)).frame(width: 12, height: 12)
                    Circle().fill(Color.secondary).frame(width: 7, height: 7)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(1)
                if case .runningTool(let name) = session.status {
                    Text("⚙️ \(name)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if case .thinking = session.status {
                    Text("Thinking…")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: session.status.icon)
                    .font(.caption)
                    .foregroundStyle(session.status.color)
                Text(session.lastMessageAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

extension View {
    @ViewBuilder func hoverEffect() -> some View {
        self.modifier(HoverHighlight())
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(hovered ? Color.primary.opacity(0.08) : Color.clear)
            .onHover { hovered = $0 }
    }
}

// MARK: - Tmux Window Row

private struct TmuxWindowRow: View {
    let window: LocalTmuxWindow

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.green.opacity(0.2)).frame(width: 12, height: 12)
                Circle().fill(Color.green).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(window.session):\(window.window)")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if !window.currentCommand.isEmpty {
                    Text(window.currentCommand)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .modifier(HoverHighlight())
    }
}

// MARK: - Local AI Process Row

private struct LocalAIRow: View {
    let process: LocalAIProcess

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.2)).frame(width: 12, height: 12)
                Circle().fill(Color.purple).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(process.name).font(.body).lineLimit(1)
                    if process.pids.count > 1 {
                        Text("×\(process.pids.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                if !process.tmuxTargets.isEmpty {
                    Text(process.tmuxTargets.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("PID \(process.pids.first ?? 0)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: process.icon)
                .font(.caption)
                .foregroundStyle(.purple)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .modifier(HoverHighlight())
    }
}
