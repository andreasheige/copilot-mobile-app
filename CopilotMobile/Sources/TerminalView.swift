import SwiftUI

struct TerminalView: View {
    let sessionId: String

    @EnvironmentObject var sessionManager: TerminalSessionManager
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var inputFocused: Bool

    private var session: TerminalSession? {
        sessionManager.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output – one visual line per output line, font scales to screen width
            GeometryReader { geo in
                let fontSize = max(9, (geo.size.width - 24) / 48.0)
                let lines = (session?.output ?? "").components(separatedBy: "\n")
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: fontSize, design: .monospaced))
                                    .foregroundStyle(CopilotTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(12)
                    }
                    .background(CopilotTheme.background)
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: session?.output) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }

            Divider().background(CopilotTheme.border)

            // Input bar – chat style
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(">")
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundStyle(CopilotTheme.accent)

                    TextField("command…", text: $inputText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(CopilotTheme.textPrimary)
                        .tint(CopilotTheme.accentLight)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($inputFocused)
                        .onSubmit(sendInput)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CopilotTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CopilotTheme.border, lineWidth: 1))

                Button(action: sendInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty ? CopilotTheme.textSecondary : CopilotTheme.accent)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CopilotTheme.background)
        }
        .navigationTitle(sessionId)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CopilotTheme.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("^C") { sessionManager.sendInput("\u{03}", to: sessionId) }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(CopilotTheme.textSecondary)
                Button("Tab") { sessionManager.sendInput("\t", to: sessionId) }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(CopilotTheme.textSecondary)
            }
        }
        .onAppear { inputFocused = true }
    }

    private func sendInput() {
        sessionManager.sendInput(inputText + "\n", to: sessionId)
        inputText = ""
    }
}
