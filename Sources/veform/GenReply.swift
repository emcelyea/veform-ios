//
//  GenReply.swift
//  conversation-app
//
//  Created by Eric McElyea on 10/7/25.
//

import Foundation

class GenReply {
    var form: Form
    var tewyWebsockets: VeWebsockets?
    private let punctuationCharacters = [".", "!", "?", ";"]
    private var genReplySentence: String = ""
    var onMessage: ((_ message: WebSocketServerMessage) -> Void)?
    init(form: Form) {
        self.form = form
    }

    func start(onMessage: @escaping (_ message: WebSocketServerMessage) -> Void) async throws {
        self.onMessage = onMessage
        VeConfig.vePrint("GENREPLY: Starting gen reply websocket connection")
        self.tewyWebsockets = VeWebsockets()
        self.tewyWebsockets?.delegate = self
        try await self.tewyWebsockets?.openConnection()
        let sessionId = try await self.tewyWebsockets?.waitForSessionId()
        VeConfig.vePrint("GENREPLY: Session id: \(sessionId)")

    }

    func handleMessage(message: WebSocketServerMessage) {
        VeConfig.vePrint("GENREPLY: Handling message: \(message.type) \(message.data ?? "")")

        if message.type == .genReplyChunk {
             if let lastChar = message.data?.last,
               punctuationCharacters.contains(String(lastChar))
            {
                genReplySentence += message.data ?? ""
                var parentMessage = message
                parentMessage.data = genReplySentence
                onMessage?(parentMessage)
                genReplySentence = ""
            } else {
                genReplySentence += message.data ?? ""
            }
        }
        if message.type == .genReplyStart || message.type == .hotPhraseSkip || message.type == .hotPhraseLast || message.type == .hotPhraseEnd || message.type == .hotPhraseMoveTo || message.type == .genReplyEnd {
            onMessage?(message)
        }
    }

   func sendMessage<T: Codable>(type: CLIENT_TO_SERVER_MESSAGES, data: T) -> Void {
       self.tewyWebsockets?.sendJSON(type:type, data:data)
   }
}

extension GenReply: TewyWebsocketsDelegate {
    func webSocketDidConnect(_: VeWebsockets) {
        VeConfig.vePrint("GENREPLY: Connected!")
    }

    func webSocketDidDisconnect(_: VeWebsockets) {
        VeConfig.vePrint("GENREPLY: Disconnected")
    }

    func webSocket(_: VeWebsockets, didReceiveMessage message: WebSocketServerMessage) {
        handleMessage(message: message)
    }

    func webSocket(_: VeWebsockets, didEncounterError error: Error) {
        VeConfig.vePrint("GENREPLY: Error: \(error)")
    }
}
