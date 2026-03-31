import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }

    @Published var terminalOrder: [String] {
        didSet { UserDefaults.standard.set(terminalOrder, forKey: "terminalOrder") }
    }

    @Published var recentStartCommands: [String] {
        didSet { UserDefaults.standard.set(recentStartCommands, forKey: "recentStartCommands") }
    }

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        self.terminalOrder = UserDefaults.standard.stringArray(forKey: "terminalOrder") ?? []
        self.recentStartCommands = UserDefaults.standard.stringArray(forKey: "recentStartCommands") ?? []
    }

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var preferredTerminal: String? { terminalOrder.first }

    func addRecentStartCommand(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        recentStartCommands.removeAll { $0 == cmd }
        recentStartCommands.insert(cmd, at: 0)
        if recentStartCommands.count > 5 { recentStartCommands = Array(recentStartCommands.prefix(5)) }
    }

    /// Converts http(s):// URL to ws(s):// with API key query param
    var wsURL: URL? {
        var urlString = serverURL.trimmingCharacters(in: .whitespaces)
        if urlString.hasPrefix("https://") {
            urlString = "wss://" + urlString.dropFirst("https://".count)
        } else if urlString.hasPrefix("http://") {
            urlString = "ws://" + urlString.dropFirst("http://".count)
        }
        if urlString.hasSuffix("/") { urlString = String(urlString.dropLast()) }
        let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        return URL(string: "\(urlString)?key=\(encoded)")
    }
}
