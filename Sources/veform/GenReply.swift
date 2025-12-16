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

    func start(onMessage: @escaping (_ message: WebSocketServerMessage) -> Void) async {
        self.onMessage = onMessage
        if VeformConfig.debug {
            print("Starting gen reply websocket connection")
        }
        self.tewyWebsockets = VeWebsockets()
        self.tewyWebsockets?.delegate = self
        print("Opening websocket connection")
        do {
            try await self.tewyWebsockets?.openConnection()
            let sessionId = try await self.tewyWebsockets?.waitForSessionId()
            print("GenReply:Session id: \(sessionId)")
        } catch {
            print("Error: \(error)")
        }
    }

    func handleMessage(message: WebSocketServerMessage) {
        if message.type == .genReplyStart {
            onMessage?(message)
        }
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
        if message.type == .genReplyEnd {
            onMessage?(message)
        }
    }

   func sendMessage<T: Codable>(type: CLIENT_TO_SERVER_MESSAGES, data: T) -> Void {
       self.tewyWebsockets?.sendJSON(type:type, data:data)
   }
}

extension GenReply: TewyWebsocketsDelegate {
    func webSocketDidConnect(_: VeWebsockets) {
        print("Connected!")
    }

    func webSocketDidDisconnect(_: VeWebsockets) {
        print("Disconnected")
    }

    func webSocket(_: VeWebsockets, didReceiveMessage message: WebSocketServerMessage) {
        handleMessage(message: message)
    }

    func webSocket(_: VeWebsockets, didEncounterError error: Error) {
        print("Error: \(error)")
    }
}
