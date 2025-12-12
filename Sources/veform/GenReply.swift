//
//  GenReply.swift
//  conversation-app
//
//  Created by Eric McElyea on 10/7/25.
//

import Foundation

enum SERVER_TO_CLIENT_MESSAGES: String {
    case sessionId = "SESSION_ID"
    case sessionNotFound = "SESSION_NOT_FOUND"
    case genReplyStart = "GEN_REPLY_START"
    case genReplyChunk = "GEN_REPLY_CHUNK"
    case genReplyEnd = "GEN_REPLY_END"
    case interrupt = "INTERRUPT"
    case error = "ERROR"
}

public enum CLIENT_TO_SERVER_MESSAGES: String {
    case initialQuestion = "INITIAL_QUESTION"
    case userMessage = "USER_MESSAGE"
    case rulesMessage = "RULES_MESSAGE"
    case genReplyRequest = "GEN_REPLY_REQUEST"
    case genReplyMessage = "GEN_REPLY_MESSAGE"
    case userMoveTo = "USER_MOVE_TO"
    case userSkip = "USER_SKIP"
    case userEnd = "USER_END"
}

struct GenReplyMessage {
    let type: SERVER_TO_CLIENT_MESSAGES
    let body: String
    init(type: SERVER_TO_CLIENT_MESSAGES, body: String) {
        self.type = type
        self.body = body
    }
}

// so order of operations is like...
class GenReply {
    var form: Form
    var tewyWebsockets: VeWebsockets?
    var sessionId: String?
    var connected: Bool = false
    private let punctuationCharacters = [".", "!", "?", ";"]
    private var genReplySentence: String = ""
    var onMessage: ((_ message: WSUnpackedMessage) -> Void)?
    init(form: Form) {
        self.form = form
    }

    // fuck gonna need to rework this so it sends the question also balls
    func start(onMessage: @escaping (_ message: WSUnpackedMessage) -> Void) async {
        self.onMessage = onMessage
        Task {
            self.tewyWebsockets = VeWebsockets()
            self.tewyWebsockets?.delegate = self
            try await self.tewyWebsockets?.openConnection()
        }
    }

    func handleMessage(message: String?) {
        var genMessage = unpackMessage(message ?? "")
        switch genMessage.type {
        case .sessionId:
            sessionId = genMessage.sessionId
        case .sessionNotFound:
            print("GenRpelys, Session not found")
        case .genReplyStart:
            onMessage?(genMessage)
        case .genReplyChunk:
            if let lastChar = genMessage.body.last,
               punctuationCharacters.contains(String(lastChar))
            {
                genReplySentence += genMessage.body
                genMessage.body = genReplySentence
                onMessage?(genMessage)
                genReplySentence = ""
            } else {
                genReplySentence += genMessage.body
            }
        case .genReplyEnd:
            onMessage?(genMessage)
        case .interrupt:
            print("GenReply, Interrupt")
        case .error:
            print("GenReply, Error")
        default:
            print("GenReply, Unknown message type")
        }
    }

//    func sendMessage(fieldId: String, type: CLIENT_TO_SERVER_MESSAGES, input: String) -> Void {
//        guard let sessionId = self.sessionId else {
//            print("WS sendMessage, No session id, message: \(input)")
//            return
//        }
//        let message = packMessage(type:type, sessionId: sessionId, fieldId: fieldId, message: input)
//        self.tewyWebsockets?.sendMessage(message)
//    }

    func sendGenReplyRequest(question: String, fieldHistory: [FieldHistory]) {
        guard let sessionId = sessionId else {
            print("WS sendMessage, No session id, message")
            return
        }
        let name = fieldHistory.first?.name ?? ""
        let header = packMessageHeader(data: [
            "type": CLIENT_TO_SERVER_MESSAGES.genReplyRequest.rawValue,
            "sessionId": sessionId,
            "question": question,
            "name": name
        ])
        let message = fieldHistory.map { $0.answer != nil ? "|user:|\($0.answer!)" : "|gen:|\($0.genReply ?? "")" ?? "" }.joined(separator: "\n")
        tewyWebsockets?.sendMessage("\(header)\n\(message)")
    }
}

extension GenReply: TewyWebsocketsDelegate {
    func webSocketDidConnect(_: VeWebsockets) {
        print("Connected!")
        connected = true
    }

    func webSocketDidDisconnect(_: VeWebsockets) {
        print("Disconnected")
        connected = false
    }

    func webSocket(_: VeWebsockets, didReceiveMessage message: String) {
        handleMessage(message: message)
    }

    func webSocket(_: VeWebsockets, didEncounterError error: Error) {
        print("Error: \(error)")
    }
}

struct WSUnpackedMessage {
    let type: SERVER_TO_CLIENT_MESSAGES?
    let sessionId: String?
    let fieldId: String?
    let genRequestId: String?
    let otherData: [String: String]?
    var body: String
}

func unpackMessage(_ message: String) -> WSUnpackedMessage {
    let components = message.components(separatedBy: "\n")
    guard !components.isEmpty else {
        return WSUnpackedMessage(
            type: nil,
            sessionId: nil,
            fieldId: nil,
            genRequestId: nil,
            otherData: [:],
            body: ""
        )
    }

    let header = components[0]
    let body = components.dropFirst().joined(separator: "\n")

    let headerParts = header.components(separatedBy: "|")

    let type = headerParts
        .first(where: { $0.hasPrefix("type:") })?
        .components(separatedBy: ":").dropFirst().joined(separator: ":")

    let sessionId = headerParts
        .first(where: { $0.hasPrefix("sessionId:") })?
        .components(separatedBy: ":").dropFirst().joined(separator: ":")

    let fieldId = headerParts
        .first(where: { $0.hasPrefix("fieldId:") })?
        .components(separatedBy: ":").dropFirst().joined(separator: ":")
    let genRequestId = headerParts
        .first(where: { $0.hasPrefix("genRequestId:") })?
        .components(separatedBy: ":").dropFirst().joined(separator: ":")

    let otherData = headerParts
        .filter { part in
            !part.hasPrefix("type:") &&
                !part.hasPrefix("sessionId:") &&
                !part.hasPrefix("fieldId:")
        }
        .reduce(into: [String: String]()) { acc, part in
            let keyValue = part.components(separatedBy: ":")
            if keyValue.count >= 2 {
                let key = keyValue[0]
                let value = keyValue.dropFirst().joined(separator: ":")
                acc[key] = value
            }
        }
    let messageType = SERVER_TO_CLIENT_MESSAGES(rawValue: type ?? "") ?? .error
    return WSUnpackedMessage(
        type: messageType,
        sessionId: sessionId,
        fieldId: fieldId,
        genRequestId: genRequestId,
        otherData: otherData,
        body: body
    )
}

func packMessageHeader(
    data: [String: String] = [:]
) -> String {
    var header = ""
    for (key, value) in data {
        header += "|\(key):\(value)"
    }

    return "\(header)"
}
