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
        if let url = settings.wsURL {
            ws.connect(to: url)
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
