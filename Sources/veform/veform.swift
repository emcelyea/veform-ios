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

public struct VeConfig {
    public static var verbose: Bool = false
    static func vePrint(_ message: String) {
        if VeConfig.verbose {
            print(message)
        }
    }
}

public class Veform {
    var form: Form?
    private var conversation: VeConversation!
    private let eventHandlers = VeformEventHandlers()
    private var loaded: Bool = false
    public init() {}

    public func start(form: Form) {
        self.form = form
        VeConfig.vePrint("VEFORM: Starting veform")
        conversation = VeConversation(form: form, eventHandlers: eventHandlers)
    }

    public func stop() {
        conversation?.stop()
    }

//    public func pauseOutput() {
//        audio?.pauseOutput()
//    }
//
//    public func resumeOutput() {
//        audio?.resumeOutput()
//    }
//
//    public func pauseListening() {
//        audio?.pauseListening()
//    }
//
//    public func resumeListening() {
//        audio?.resumeListening()
//    }

    public func setCurrentField(name: String) {
        conversation?.setCurrentField(name: name)
    }

//    public func getConversationState() -> ConversationState {
//        return conversation.getConversationState()
//    }

    public func setFieldState(name: String, state: ConversationStateEntry) {
        conversation.setFieldState(name: name, state: state)
    }
    
    public func onLoadingStarted(callback: @escaping () -> Void) {
        eventHandlers.onLoadingStarted = callback
    }

    public func onLoadingFinished(callback: @escaping () -> Void) {
        eventHandlers.onLoadingFinished = callback
    }

    public func onRunningStarted(callback: @escaping () -> Void) {
        eventHandlers.onRunningStarted = callback
    }

    public func onRunningFinished(callback: @escaping () -> Void) {
        eventHandlers.onRunningFinished = callback
    }

    public func onAudioInStart(callback: @escaping () -> Void) {
        eventHandlers.onAudioInStart = callback
    }
    public func onAudioInChunk(callback: @escaping (String) -> Void) {
        eventHandlers.onAudioInChunk = callback
    }
    public func onAudioInEnd(callback: @escaping (String) -> Void) {
        eventHandlers.onAudioInEnd = callback
    }
    public func onAudioOutStart(callback: @escaping (String) -> Bool?) {
        eventHandlers.onAudioOutStart = callback
    }
    public func onAudioOutEnd(callback: @escaping () -> Void) {
        eventHandlers.onAudioOutEnd = callback
    }
    public func onListening(callback: @escaping () -> Void) {
        eventHandlers.onListening = callback
    }
    public func onSpeaking(callback: @escaping () -> Void) {
        eventHandlers.onSpeaking = callback
    }
    public func onFieldChanged(callback: @escaping (_ previous: ConversationStateEntry, _ next: ConversationStateEntry) -> Bool?) {
        eventHandlers.onFieldChanged = callback
    }
    public func onComplete(callback: @escaping (ConversationState) -> Void) {
        eventHandlers.onComplete = callback
    }
    public func onError(callback: @escaping (String) -> Void) {
        eventHandlers.onError = callback
    }
}


public class VeformEventHandlers {
    var onLoadingStarted: (() -> Void)?
    var onLoadingFinished: (() -> Void)?
    var onRunningStarted: (() -> Void)?
    var onRunningFinished: (() -> Void)?
    var onAudioInStart: (() -> Void)?
    var onAudioInChunk: ((String) -> Void)?
    var onAudioInEnd: ((String) -> Void)?
    var onAudioOutStart: ((String) -> Bool?)?
    var onAudioOutEnd: (() -> Void)?
    var onListening: (() -> Void)?
    var onSpeaking: (() -> Void)?
    var onFieldChanged: ((_ previous: ConversationStateEntry, _ next: ConversationStateEntry) -> Bool?)?
    var onError: ((String) -> Void)?
    var onComplete: ((ConversationState) -> Void)?
    
    func loadingStarted() {
        if let handler = onLoadingStarted {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func loadingFinished() {
        if let handler = onLoadingFinished {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func runningStarted() {
        if let handler = onRunningStarted {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func runningFinished() {
        if let handler = onRunningFinished {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func audioInStart() -> Void {
        if let handler = onAudioInStart {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func audioInChunk(_ data: String) -> Void {
        if let handler = onAudioInChunk {
            DispatchQueue.main.async {
                handler(data)
            }
        }
    }
    
    func audioInEnd(_ data: String) -> Void {
        if let handler = onAudioInEnd {
            DispatchQueue.main.async {
                handler(data)
            }
        }
    }
    
    func audioOutStart(_ data: String) -> Bool? {
        if let handler = onAudioOutStart {
            DispatchQueue.main.sync {
                return handler(data)
            }
        }
        return false
    }
    
    func audioOutEnd() -> Void {
        if let handler = onAudioOutEnd {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func listening() {
        if let handler = onListening {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func speaking() {
        if let handler = onSpeaking {
            DispatchQueue.main.async {
                handler()
            }
        }
    }
    
    func fieldChanged(previous: ConversationStateEntry, next: ConversationStateEntry) -> Bool? {
        if let handler = onFieldChanged {
            DispatchQueue.main.sync {
                return handler(previous, next)
            }
        }
        return false
    }
    
    func complete(conversationState: ConversationState) {
        if let handler = onComplete {
            DispatchQueue.main.async {
                handler(conversationState)
            }
        }
    }
    func error(error: String) {
        if let handler = onError {
            DispatchQueue.main.async {
                handler(error)
            }
        }
    }
}
