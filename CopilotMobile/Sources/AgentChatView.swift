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
            Divider()
            inputBar
        }
        .navigationTitle(session?.title ?? "Copilot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if agentManager.isResponding { ProgressView().scaleEffect(0.8) }
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
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Copilot…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...6)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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
                    Text("Running `\(tc.tool)`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView().scaleEffect(0.6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
            }

            // Message content
            if !message.content.isEmpty || message.toolCalls.isEmpty {
                HStack {
                    if message.role == .user { Spacer(minLength: 60) }

                    Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(message.role == .user ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)

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
