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
        Task {
            self.tewyWebsockets = VeWebsockets()
            self.tewyWebsockets?.delegate = self
            try await self.tewyWebsockets?.openConnection()
        }
    }

    func handleMessage(message: WebSocketServerMessage) {
        if message.type == SERVER_TO_CLIENT_MESSAGES.GEN_REPLY_START {
            onMessage?(message)
        }
        if message.type == SERVER_TO_CLIENT_MESSAGES.GEN_REPLY_CHUNK {
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
        }
        if message.type == SERVER_TO_CLIENT_MESSAGES.GEN_REPLY_END {
            onMessage?(message)
        }
    }

   func sendMessage<T: Codable>(type: CLIENT_TO_SERVER_MESSAGES, data: T) -> Void {
       self.tewyWebsockets?.sendJSON(type, data)
   }
}

extension GenReply: TewyWebsocketsDelegate {
    func webSocketDidConnect(_: VeWebsockets) {
        print("Connected!")
    }

    func webSocketDidDisconnect(_: VeWebsockets) {
        print("Disconnected")
    }

    func webSocket(_: VeWebsockets, didReceiveMessage message: String) {
        handleMessage(message: message)
    }

    func webSocket(_: VeWebsockets, didEncounterError error: Error) {
        print("Error: \(error)")
    }
}
