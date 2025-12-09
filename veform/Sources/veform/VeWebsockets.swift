import Foundation
import Network

protocol TewyWebsocketsDelegate: AnyObject {
    func webSocketDidConnect(_ webSocket: VeWebsockets)
    func webSocketDidDisconnect(_ webSocket: VeWebsockets)
    func webSocket(_ webSocket: VeWebsockets, didReceiveMessage message: String)
    func webSocket(_ webSocket: VeWebsockets, didEncounterError error: Error)
}

enum WebSocketState {
    case disconnected
    case connecting
    case connected
    case disconnecting
}
let urlWs = "wss://5f064a7cf2b8.ngrok-free.app"
internal class VeWebsockets: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let url: URL
    private var connectionCompletion: ((Result<Void, Error>) -> Void)?
    var state: WebSocketState = .disconnected
    var lastError: Error?
    weak var delegate: TewyWebsocketsDelegate?

    init() {
        self.url = URL(string: urlWs + "/conversation")!
        print("WebSocket URL: \(self.url)")
        setupURLSession()
    }

    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config)
    }

    func openConnection() async throws {
        print("OPENING WS CONNECTION")
        // If already connected, return immediately
        if state == .connected {
            return
        }

        // If already connecting, wait for the existing connection attempt
        if state == .connecting {
            try await withCheckedThrowingContinuation { continuation in
                self.connectionCompletion = { result in
                    continuation.resume(with: result)
                }
            }
            return
        }

        state = .connecting
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        print("ADDING TASK GROUP")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.connectionCompletion = { result in
                        continuation.resume(with: result)
                    }
                    print("STARTING LISTENING")
                    self.startListening()
                }
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw WebSocketError.connectionFailed
            }

            // Wait for either connection or timeout
            try await group.next()
            group.cancelAll()
        }
    }

    func closeConnection() {
        guard state == .connected || state == .connecting else {
            print("WebSocket: Not connected")
            return
        }

        state = .disconnecting
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        delegate?.webSocketDidDisconnect(self)
    }

    func sendMessage(_ message: String) {
        guard state == .connected else {
            let error = WebSocketError.notConnected
            print("WS sendmessage while not connected: \(error)")
            return
        }

        let message = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error, let self = self {
               self.delegate?.webSocket(self, didEncounterError: error)
            }
        }
    }

    func sendJSON<T: Codable>(_ object: T) {
        do {
            let jsonData = try JSONEncoder().encode(object)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            sendMessage(jsonString)
        } catch {
            delegate?.webSocket(self, didEncounterError: error)
        }
    }

    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(message):
                self.handleMessage(message)
                self.startListening()
            case let .failure(error):
                self.state = .disconnected
                self.delegate?.webSocket(self, didEncounterError: error)
                self.connectionCompletion?(.failure(error))
                self.connectionCompletion = nil
                print("WS startlistening error: \(error)")
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case let .string(text):
            if self.state == .connecting {
                print("setting to connected")
                self.state = .connected
                self.delegate?.webSocketDidConnect(self)
                self.connectionCompletion?(.success(()))
                self.connectionCompletion = nil
            }
            self.delegate?.webSocket(self, didReceiveMessage: text)

        // case let .data(data):
        //     // Convert data to  string if possible
        //     if let text = String(data: data, encoding: .utf8) {
        //         DispatchQueue.main.async {
        //             if self.state == .connecting {
        //                 self.state = .connected
        //                 self.onEvent?(.connected)
        //                 // Complete the connection promise
        //                 self.connectionCompletion?(.success(()))
        //                 self.connectionCompletion = nil
        //             }
        //             self.onEvent?(.message(text))
        //         }
        //     }

        @unknown default:
            print("WS: Unknown message type received")
        }
    }

    deinit {
        closeConnection()
    }
}

// MARK: - WebSocket Errors

enum WebSocketError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case connectionFailed
    case jsonEncodingFailed
    case jsonDecodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .notConnected:
            return "WebSocket is not connected"
        case .connectionFailed:
            return "Failed to establish WebSocket connection"
        case .jsonEncodingFailed:
            return "Failed to encode object to JSON"
        case .jsonDecodingFailed:
            return "Failed to decode JSON data"
        }
    }
}
