import SwiftUI

struct SessionListView: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var ws: TerminalWebSocketManager
    @EnvironmentObject var sessionManager: TerminalSessionManager
    @EnvironmentObject var settings: AppSettings

    @State private var showNewSession = false

    var body: some View {
        List(selection: Binding(
            get: { sessionManager.activeSessionId },
            set: { sessionManager.activeSessionId = $0 }
        )) {
            ForEach(sessionManager.sessions) { session in
                NavigationLink(value: session.id) {
                    SessionRow(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        sessionManager.closeSession(session.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Terminal")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gear") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(ws.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Button { showNewSession = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!ws.isConnected)
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet { name, path, cmd in
                sessionManager.newSession(name: name, workDir: path, startCommand: cmd, preferredTerminal: settings.preferredTerminal)
                showNewSession = false
            }
        }
    }
}

struct NewSessionSheet: View {
    var onCreate: (String, String, String) -> Void

    @EnvironmentObject var sessionManager: TerminalSessionManager
    @EnvironmentObject var settings: AppSettings
    @State private var sessionName: String = ""
    @State private var workPath: String = ""
    @State private var startCommand: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session name (optional)", text: $sessionName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Session Name")
                } footer: {
                    Text("Leave blank for auto-generated name")
                }

                Section {
                    TextField("e.g. ~/Work/my-repo", text: $workPath)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Working Directory")
                }

                Section("Recent Paths") {
                    ForEach(sessionManager.recentPaths, id: \.path) { item in
                        Button {
                            workPath = item.path
                        } label: {
                            HStack {
                                Text(item.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if item.label != item.path {
                                    Text(item.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if workPath == item.path {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section {
                    TextField("e.g. gh copilot, npm start", text: $startCommand)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Startup Command")
                } footer: {
                    Text("Runs automatically when the terminal opens. Leave blank for a plain shell.")
                }

                if !settings.recentStartCommands.isEmpty {
                    Section("Recent Commands") {
                        ForEach(settings.recentStartCommands, id: \.self) { cmd in
                            Button {
                                startCommand = cmd
                            } label: {
                                HStack {
                                    Text(cmd)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if startCommand == cmd {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle("New Terminal Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        let name = sessionName.trimmingCharacters(in: .whitespaces)
                        let path = workPath.trimmingCharacters(in: .whitespaces)
                        let cmd = startCommand.trimmingCharacters(in: .whitespaces)
                        let finalName = name.isEmpty ? "session-\(Int(Date().timeIntervalSince1970) % 10000)" : name
                        if !cmd.isEmpty { settings.addRecentStartCommand(cmd) }
                        onCreate(finalName, path, cmd)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SessionRow: View {
    let session: TerminalSession

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle:    return .yellow
        case .stale:   return .orange
        case .ended:   return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.id)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(session.status.label)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                if !session.workDir.isEmpty {
                    Text(session.workDir)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(session.createdAt.formatted(.dateTime.hour().minute().second()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

