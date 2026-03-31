import SwiftUI

struct AgentChatView: View {
    let sessionId: String
    @EnvironmentObject var agentManager: AgentSessionManager
    @EnvironmentObject var ws: TerminalWebSocketManager
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?

    private var session: AgentSession? {
        agentManager.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider().background(CopilotTheme.border)
            inputBar
        }
        .background(CopilotTheme.background)
        .navigationTitle(session?.title ?? "Copilot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CopilotTheme.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if agentManager.isResponding {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(CopilotTheme.accent)
                }
            }
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(session?.messages ?? []) { message in
                        AgentMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .background(CopilotTheme.background)
            .onAppear { scrollProxy = proxy }
            .onChange(of: session?.messages.count) { scrollToBottom() }
            .onChange(of: session?.messages.last?.content) { scrollToBottom() }
        }
    }

    private func scrollToBottom() {
        guard let last = session?.messages.last else { return }
        withAnimation(.easeOut(duration: 0.15)) { scrollProxy?.scrollTo(last.id, anchor: .bottom) }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Copilot…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(CopilotTheme.textPrimary)
                .tint(CopilotTheme.accentLight)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CopilotTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CopilotTheme.border, lineWidth: 1))
                .lineLimit(1...6)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? CopilotTheme.accent : CopilotTheme.textSecondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CopilotTheme.background)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ws.isConnected && !agentManager.isResponding
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        agentManager.sendMessage(text, in: sessionId)
    }
}

// MARK: - Message bubble

struct AgentMessageView: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            // Tool call indicators
            ForEach(message.toolCalls) { tc in
                HStack(spacing: 6) {
                    Image(systemName: toolIcon(tc.tool))
                        .font(.caption)
                        .foregroundStyle(CopilotTheme.accentLight)
                    Text("Running `\(tc.tool)`")
                        .font(.caption)
                        .foregroundStyle(CopilotTheme.textSecondary)
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(CopilotTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(CopilotTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(CopilotTheme.border, lineWidth: 1))
            }

            // Message content
            if !message.content.isEmpty || message.toolCalls.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    if message.role == .user { Spacer(minLength: 60) }

                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        // Role label for assistant
                        if message.role == .assistant {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(CopilotTheme.accent)
                                Text("Copilot")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(CopilotTheme.textSecondary)
                            }
                        }

                        Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(message.role == .user ? CopilotTheme.accent : CopilotTheme.surface)
                            .foregroundStyle(message.role == .user ? Color.white : CopilotTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                message.role == .assistant
                                    ? RoundedRectangle(cornerRadius: 16).stroke(CopilotTheme.border, lineWidth: 1)
                                    : nil
                            )
                            .textSelection(.enabled)
                    }

                    if message.role == .assistant { Spacer(minLength: 60) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func toolIcon(_ tool: String) -> String {
        switch tool {
        case "bash": return "terminal"
        case "read_file": return "doc.text"
        case "write_file": return "pencil"
        case "list_dir": return "folder"
        default: return "wrench"
        }
    }
}
