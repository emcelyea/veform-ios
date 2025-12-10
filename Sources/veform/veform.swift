//
//  veform.swift
//  veform
//
//  Created by Eric McElyea on 11/30/25.
//

import Foundation

struct ConversationSetupState {
    var setupComplete: Bool
    var lastConversationEvent: ConversationEvent?
    var pipeGenReply: Bool
}

public class Veform {
    var form: Form?
    private var isWebsocketSetup: Bool = false
    private var isAudioSetup: Bool = false
    private var lastConversationEvent: ConversationEvent?
    private var audio: VeAudio!
    private var conversation: VeConversation!
    private var state: ConversationSetupState = .init(setupComplete: false,
                                                      lastConversationEvent: nil,
                                                      pipeGenReply: false)
    private var parentCallback: ((ConversationEvent, ConversationStateEntry) -> Void)?
    private var parentCompleteCallback: ((ConversationState) -> Void)?
    public init() {}

    public func start(formId _: String) {
        Task {
            do {
                let request = VeHttp()
                let formData = try await request.getForm(id: "1")
                guard let form = formData else {
                    print("Form is nil")
                    return
                }
                self.form = form
                audio = VeAudio(emitEvent: self.handleEvent)
                conversation = VeConversation(form: form, emitEvent: self.handleEvent, onComplete: self.end)
            } catch {
                print("Error getting form: \(error)")
            }
        }
        print("Done with taks")
    }

    public func stop() {
        audio?.stop()
        conversation?.stop()
    }

    public func pauseOutput() {
        audio?.pauseOutput()
    }

    public func resumeOutput() {
        audio?.resumeOutput()
    }

    public func pauseListening() {
        audio?.pauseListening()
    }

    public func resumeListening() {
        audio?.resumeListening()
    }

    public func setCurrentField(name: String) {
        let field = form?.fields.first(where: { $0.name == name })
        guard let field = field else {
            print("Field not found")
            return
        }
        let id = field.id
        conversation?.setCurrentField(id: id)
    }

    public func getConversationState() -> ConversationState {
        return conversation.getConversationState()
    }

    public func setFieldState(id: String, state: ConversationStateEntry) {
        conversation.setFieldState(id: id, state: state)
    }

    public func onEvent(callback: @escaping (ConversationEvent, ConversationStateEntry) -> Void) {
        parentCallback = callback
    }

    public func onComplete(callback: @escaping (ConversationState) -> Void) {
        parentCompleteCallback = callback
    }

    func end(fields: ConversationState) {
        if let parentCompleteCallback = parentCompleteCallback {
            parentCompleteCallback(fields)
        }
        audio.stopWhenDone()
        conversation.stop()
    }

    // ok this is dumb, go pee and then this should fire a valid answer event not a fuckin audioInMessage event
    func handleEvent(event: ConversationEvent, data: String? = nil) {
        let fieldBeforeEvent = conversation.getCurrentField()
        // yeh I am dumb, this shit needs ot dispatch conversationEventData
        // then we can map it to entries for the end
        if event == .websocketSetup {
            isWebsocketSetup = true
            if shouldSendInitialMessage() {
                conversation.start()
            }
        } else if event == .audioSetup {
            isAudioSetup = true
            if shouldSendInitialMessage() {
                conversation.start()
            }
        } else if event == .audioInMessage {
            if !state.setupComplete { return }
            guard let data = data else { return }
            conversation.inputReceived(input: data)
        } else if event == .audioOutMessage {
            guard let data = data else { return }
            audio.output(data)
        } else if event == .genReplyRequestStart {
            audio.pauseListening()
        } else if event == .genReplyRequestEnd {
            audio.resumeListening()
        } else if event == .error {
            print("ERROR: \(data ?? "Unknown error")")
        }
        if parentCallback != nil, event != .audioSetup, event != .websocketSetup {
            if !state.setupComplete { return }
            let stateEntry = conversation.getFieldStateEntry(id: fieldBeforeEvent?.id ?? "")
            print("preparing to hit parentcallback \(event)")
            guard let stateEntry = stateEntry else {
                print("State entry not found")
                return
            }
            print("hit parentcallback with entry \(event) \(stateEntry)")
            DispatchQueue.main.async { [weak self] in
                print("HITTING PARENT CALLBACK \(event) \(stateEntry)")
                self?.parentCallback?(event, stateEntry)
            }
        }
   
    }

    func shouldSendInitialMessage() -> Bool {
        let isSetupComplete = isWebsocketSetup && isAudioSetup
        if isSetupComplete {
            if state.setupComplete {
                return false
            }
            state.setupComplete = true
            return true
        }
        return false
    }
}
