import SwiftUI

struct TerminalView: View {
    let sessionId: String

    @EnvironmentObject var sessionManager: TerminalSessionManager
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    private var session: TerminalSession? {
        sessionManager.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(session?.output ?? "")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("bottom")
                }
                .background(Color.black)
                .onChange(of: session?.output) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            Divider().background(Color.gray.opacity(0.4))

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("command", text: $inputText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .onSubmit { sendInput() }

                Button(action: sendInput) {
                    Image(systemName: "return").foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black)
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("^C") { sessionManager.sendInput("\u{03}", to: sessionId) }
                    .font(.system(.caption, design: .monospaced))
                Button("Tab") { sessionManager.sendInput("\t", to: sessionId) }
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .onAppear { inputFocused = true }
    }

    private func sendInput() {
        sessionManager.sendInput(inputText + "\n", to: sessionId)
        inputText = ""
    }
}
