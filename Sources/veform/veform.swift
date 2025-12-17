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

struct VeConfig {
    static var verbose: Bool = false
    static func vePrint(_ message: String) {
        if VeConfig.verbose {
            print(message)
        }
    }
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
    private var parentCallback: ((ConversationEvent, ConversationStateEntry?) -> Void)?
    private var parentCompleteCallback: ((ConversationState) -> Void)?
    public init() {}

    public func start(form: Form) {
        self.form = form
        handleEvent(event: .loadingStarted)
        VeConfig.vePrint("VEFORM: Starting veform")
        audio = VeAudio(emitEvent: self.handleEvent)
        conversation = VeConversation(form: form, emitEvent: self.handleEvent, onComplete: self.end)
    }

    public func setLogging(verbose: Bool) {
        VeConfig.verbose = verbose
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
        conversation?.setCurrentField(name: name)
    }

    public func getConversationState() -> ConversationState {
        return conversation.getConversationState()
    }

    public func setFieldState(name: String, state: ConversationStateEntry) {
        conversation.setFieldState(name: name, state: state)
    }

    public func onEvent(callback: @escaping (ConversationEvent, ConversationStateEntry?) -> Void) {
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
        handleEvent(event: .runningFinished)
    }

    func handleEvent(event: ConversationEvent, data: String? = nil) {
        print("veform, handling event: \(event) \(data)")
        if event == .websocketSetup {
            isWebsocketSetup = true
            if shouldSendInitialMessage() {
                handleEvent(event: .loadingFinished)
                handleEvent(event: .runningStarted)
                conversation.start()
            }
        } else if event == .audioSetup {
            isAudioSetup = true
            if shouldSendInitialMessage() {
                handleEvent(event: .loadingFinished)
                handleEvent(event: .runningStarted)
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
            VeConfig.vePrint("VEFORM: ERROR: \(data ?? "Unknown error")")
            if isAudioSetup {
                audio.output("We are having an issue please try again later.", block:true, purge:true)
                audio.stopWhenDone()
                handleEvent(event: .runningFinished)
            }
            if isWebsocketSetup {
                conversation.stop()
                handleEvent(event: .runningFinished)
            }
        }
        if parentCallback != nil, event != .audioSetup, event != .websocketSetup {
            print("veform, passing event to parent: \(event)")
            if event == .loadingStarted {
                print("veform, passing loading started to parent")
                DispatchQueue.main.async {[weak self] in
                    self?.parentCallback?(event, nil)
                }
            }
            if !state.setupComplete { return }
            let fieldBeforeEvent = conversation.getCurrentField()
            let stateEntry = conversation.getFieldStateEntry(name: fieldBeforeEvent?.name ?? "")
            guard let stateEntry = stateEntry else {
                VeConfig.vePrint("VEFORM: State entry not found")
                return
            }
            DispatchQueue.main.async { [weak self] in
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
