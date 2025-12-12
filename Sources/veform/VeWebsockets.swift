import Foundation
import Network

protocol TewyWebsocketsDelegate: AnyObject {
    func webSocketDidConnect(_ webSocket: VeWebsockets)
    func webSocketDidDisconnect(_ webSocket: VeWebsockets)
    func webSocket(_ webSocket: VeWebsockets, didReceiveMessage message: WebSocketServerMessage)
    func webSocket(_ webSocket: VeWebsockets, didEncounterError error: Error)
}

enum SERVER_TO_CLIENT_MESSAGES: String, Codable {
    case sessionId = "SESSION_ID"
    case sessionNotFound = "SESSION_NOT_FOUND"
    case genReplyStart = "GEN_REPLY_START"
    case genReplyChunk = "GEN_REPLY_CHUNK"
    case genReplyEnd = "GEN_REPLY_END"
    case interrupt = "INTERRUPT"
    case error = "ERROR"
}

public enum CLIENT_TO_SERVER_MESSAGES: String, Codable {
    case setupForm = "SETUP_FORM"
    case genReplyRequest = "GEN_REPLY_REQUEST"
}

enum WebSocketState {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

struct WebSocketClientMessage<T: Codable>: Codable {
    let type: CLIENT_TO_SERVER_MESSAGES
    let sessionId: String
    let data: T
}

struct WebSocketServerMessage: Codable {
    let type: SERVER_TO_CLIENT_MESSAGES
    let sessionId: String?
    let genRequestId: String?
    let fieldName: String?
    var data: String?
    let valid: Bool?
    let skip: Bool?
    let last: Bool?
    let end: Bool?
    let moveToId: String?
    let validYes: Bool?
    let validNo: Bool?
    let number: Double?
    let selectOption: String?
    let selectOptions: String?
}

let urlWs = "wss://5f064a7cf2b8.ngrok-free.app"
class VeWebsockets: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let url: URL
    private var connectionCompletion: ((Result<Void, Error>) -> Void)?
    var state: WebSocketState = .disconnected
    var lastError: Error?
    weak var delegate: TewyWebsocketsDelegate?
    var sessionId: String?
    init() {
        url = URL(string: urlWs + "/conversation")!
        print("WebSocket URL: \(url)")
        setupURLSession()
    }

    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config)
    }

    func openConnection() async throws {
        if state == .connected {
            return
        }

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

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.connectionCompletion = { result in
                        continuation.resume(with: result)
                    }
                    self.startListening()
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw WebSocketError.connectionFailed
            }
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

    func sendJSON<T: Codable>(type: CLIENT_TO_SERVER_MESSAGES, data: T) {
        guard let sessionId = sessionId else {
            print("WS sendMessage, No session id")
            return
        }
        guard state == .connected else {
            let error = WebSocketError.notConnected
            print("WS sendmessage while not connected: \(error)")
            return
        }

        do {
            let message = WebSocketClientMessage(type: type, sessionId: sessionId, data: data)
            let jsonData = try JSONEncoder().encode(message)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            let messageJson = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(messageJson) { [weak self] error in
                if let error = error, let self = self {
                    self.delegate?.webSocket(self, didEncounterError: error)
                }
            }
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
            if state == .connecting {
                print("setting to connected")
                state = .connected
                delegate?.webSocketDidConnect(self)
                connectionCompletion?(.success(()))
                connectionCompletion = nil
            }
            do {
                let serverMessage = try JSONDecoder().decode(WebSocketServerMessage.self, from: text.data(using: .utf8)!)
                if serverMessage.type == SERVER_TO_CLIENT_MESSAGES.sessionId {
                    sessionId = serverMessage.sessionId
                    return
                }
                if serverMessage.type == SERVER_TO_CLIENT_MESSAGES.sessionNotFound {
                    print("WS: Session not found \(serverMessage.data ?? "No data")")
                    return
                }
                if serverMessage.type == SERVER_TO_CLIENT_MESSAGES.error {
                    print("WS: Error: \(serverMessage.data ?? "No data")")
                    return
                }
                if serverMessage.type == SERVER_TO_CLIENT_MESSAGES.interrupt {
                    print("WS: Interrupt \(serverMessage.data ?? "No data")")
                    return
                }
                delegate?.webSocket(self, didReceiveMessage: serverMessage)
            } catch {
                print("WS: Error decoding message: \(error)")
                return
            }
        case let .data(data):
            print("WS: Data message received \(data.count)")
            return
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
