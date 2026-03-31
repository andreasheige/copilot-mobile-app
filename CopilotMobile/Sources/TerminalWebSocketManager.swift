import Foundation

@MainActor
final class TerminalWebSocketManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?

    var onMessage: ((WSMessage) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    private var pingTask: Task<Void, Never>?
    private var reconnectURL: URL?
    private var reconnectTask: Task<Void, Never>?

    func connect(to url: URL) {
        reconnectURL = url
        reconnectTask?.cancel()
        disconnect(clearURL: false)
        connectionError = nil
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()
        isConnected = true
        listen()
        startPing()
    }

    func disconnect(clearURL: Bool = true) {
        pingTask?.cancel()
        pingTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        if clearURL { reconnectURL = nil }
    }

    func send(_ msg: WSMessage) {
        guard let ws = webSocket,
              let data = try? JSONEncoder().encode(msg),
              let text = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(text)) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    self?.connectionError = error.localizedDescription
                    self?.scheduleReconnect()
                }
            }
        }
    }

    private func listen() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handle(msg)
                    self.listen()
                case .failure(let err):
                    self.isConnected = false
                    self.connectionError = err.localizedDescription
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(WSMessage.self, from: data)
        else { return }
        onMessage?(msg)
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { send(WSMessage(type: "ping")) }
            }
        }
    }

    private func scheduleReconnect() {
        guard let url = reconnectURL else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { connect(to: url) }
        }
    }
}
