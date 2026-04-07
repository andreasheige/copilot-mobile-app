import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ws: TerminalWebSocketManager
    @Binding var isPresented: Bool

    @State private var serverURLDraft = ""
    @State private var apiKeyDraft = ""
    @State private var isTestingConnection = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://your-tunnel.trycloudflare.com", text: $serverURLDraft)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Your secret API key", text: $apiKeyDraft)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Enter the public URL from your Cloudflare Tunnel and the API_KEY you set in your server's .env file.")
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTestingConnection ? "Testing…" : "Test Connection")
                        }
                    }
                    .disabled(serverURLDraft.isEmpty || apiKeyDraft.isEmpty || isTestingConnection)

                    if let result = testResult {
                        switch result {
                        case .success:
                            Label("Connected successfully", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }

                Section("Terminal") {
                    NavigationLink("Terminal Order") {
                        TerminalOrderView()
                    }
                }

                Section("How to Set Up") {
                    Link("View Setup Guide on GitHub", destination: URL(string: "https://github.com")!)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick steps:")
                            .font(.caption.bold())
                        Text("1. Copy server/.env.example → .env\n2. Add your GitHub token & API key\n3. Run: cd server && npm start\n4. Run: cloudflared tunnel --url http://localhost:3000\n5. Paste the tunnel URL above")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(serverURLDraft.isEmpty || apiKeyDraft.isEmpty)
                    .fontWeight(.semibold)
                }

                if settings.isConfigured {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
            .onAppear {
                serverURLDraft = settings.serverURL
                apiKeyDraft = settings.apiKey
            }
        }
    }

    private func save() {
        settings.serverURL = serverURLDraft
        settings.apiKey = apiKeyDraft
        if let request = settings.wsRequest {
            ws.connect(to: request)
        }
        isPresented = false
    }

    private func testConnection() {
        guard let baseURL = URL(string: serverURLDraft.trimmingCharacters(in: .whitespaces)) else {
            testResult = .failure("Invalid URL")
            return
        }
        isTestingConnection = true
        testResult = nil

        let healthURL = baseURL.appendingPathComponent("health")
        URLSession.shared.dataTask(with: healthURL) { data, response, error in
            DispatchQueue.main.async {
                isTestingConnection = false
                if let error {
                    testResult = .failure(error.localizedDescription)
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    testResult = .failure("Server returned an error")
                    return
                }
                testResult = .success
            }
        }.resume()
    }
}

struct TerminalOrderView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var terminals: [String] = []
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                ForEach(terminals, id: \.self) { terminal in
                    HStack {
                        Image(systemName: terminalIcon(terminal))
                            .foregroundStyle(.secondary)
                        Text(terminal)
                        if terminals.first == terminal {
                            Spacer()
                            Text("Preferred")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .onMove { from, to in
                    terminals.move(fromOffsets: from, toOffset: to)
                    settings.terminalOrder = terminals
                }
            } footer: {
                Text("First terminal in list is used when opening sessions from your phone.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Terminal Order")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { fetchTerminals() } label: {
                    if isLoading { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .onAppear { fetchTerminals() }
    }

    private func terminalIcon(_ name: String) -> String {
        switch name {
        case "Warp": return "terminal.fill"
        case "Ghostty": return "terminal"
        case "kitty": return "terminal"
        case "iTerm2": return "terminal"
        default: return "terminal"
        }
    }

    private func fetchTerminals() {
        guard !settings.serverURL.isEmpty, !settings.apiKey.isEmpty else { return }
        isLoading = true
        let urlStr = settings.serverURL.trimmingCharacters(in: .whitespaces)
        guard let base = URL(string: urlStr) else { isLoading = false; return }
        let terminalsURL = base.appendingPathComponent("api/terminals")
        var request = URLRequest(url: terminalsURL)
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                guard let data,
                      let json = try? JSONDecoder().decode([String: [String]].self, from: data),
                      let detected = json["terminals"] else { return }
                var merged = settings.terminalOrder.filter { detected.contains($0) }
                for t in detected where !merged.contains(t) { merged.append(t) }
                terminals = merged
                settings.terminalOrder = merged
            }
        }.resume()
    }
}
