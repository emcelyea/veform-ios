//
//  veform.swift
//  veform
//
//  Created by Eric McElyea on 11/30/25.
//

import Foundation
import AVFoundation
import WebRTC

private let defaultServerURL = "wss://api.veform.co/veform-api/ws"

public struct VeConfig {
    public static var verbose: Bool = false
    static func vePrint(_ message: String) {
        if VeConfig.verbose {
            print(message)
        }
    }
}

public class Veform {
    private var form: Form?
    private var wsSession: URLSession?
    private var wsConnection: URLSessionWebSocketTask?
    private var peerConnection: RTCPeerConnection?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private let eventHandlers = VeformEventHandlers()
    public static var running: Bool = false
    public var debug: Bool = false
    public var verbose: Bool = false
    public private(set) var finished: Bool = false

    public init(builder: FormBuilder) {
        self.form = builder.form
    }

    @discardableResult
    public func start(token: String) async -> Bool {
        guard !Veform.running else {
            log("start called while already started", type: .error)
            return false
        }
        Veform.running = true

        guard let form, !form.fields.isEmpty else {
            log("No fields provided", type: .error)
            Veform.running = false
            eventHandlers.criticalError(error: "No fields provided")
            return false
        }
        if token.isEmpty {
            eventHandlers.criticalError(error: "No token provided")
            Veform.running = false
            return false
        }
        createAudioElement()
        let permissionsGranted = await requestPermissions()
        if !permissionsGranted {
            eventHandlers.criticalError(error: "Microphone permission denied")
            Veform.running = false
            return false
        }
        configureAudioSession()
        eventHandlers.loadingStarted()

        guard
            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let wsURL = URL(string: defaultServerURL + "?token=" + encodedToken)
        else {
            eventHandlers.criticalError(error: "Invalid websocket URL")
            Veform.running = false
            return false
        }

        wsSession = URLSession(configuration: .default)
        wsConnection = wsSession?.webSocketTask(with: wsURL)
        wsConnection?.resume()
        log("WS connection opened", type: .debug)
        listenForMessages()

        return true

    }


    public func stop() {
        wsConnection?.cancel(with: .normalClosure, reason: nil)
        wsConnection = nil
        wsSession?.invalidateAndCancel()
        wsSession = nil
        Veform.running = false
    }

    // TS-style API parity
    public func emitAudio(_ audio: String, interrupt: Bool = false) {
        guard Veform.running else {
            log("emitAudio called before connection was established", type: .error)
            return
        }

        eventHandlers.error(error: "emitAudio is not currently supported in veform-ios")
        log("emitAudio not supported yet. Requested audio=\(audio), interrupt=\(interrupt)", type: .warn)
    }

    public func changeField(_ fieldName: String) {
        guard Veform.running else {
            log("changeField called before connection was established", type: .error)
            return
        }
    }

    public func interrupt() {
        guard Veform.running else {
            log("interrupt called before connection was established", type: .error)
            return
        }
        // Existing protocol has no interrupt message; this is currently a no-op.
        eventHandlers.error(error: "interrupt is not currently supported in veform-ios")
        log("interrupt not supported yet", type: .warn)
    }

    public func onLoadingStarted(callback: @escaping () -> Void) {
        eventHandlers.onLoadingStarted = callback
    }

    public func onRunningStarted(callback: @escaping () -> Void) {
        eventHandlers.onRunningStarted = callback
    }

    public func onFinished(callback: @escaping () -> Void) {
        eventHandlers.onFinished = callback
    }

    public func onAudioInStart(callback: @escaping () -> Void) {
        eventHandlers.onAudioInStart = callback
    }
    public func onAudioInChunk(callback: @escaping (String) -> Void) {
        eventHandlers.onAudioInChunk = callback
    }
    // blocking this will prevent conversation replying, validation and moving to the next field
    public func onAudioInEnd(callback: @escaping (String) -> Bool?) {
        eventHandlers.onAudioInEnd = callback
    }
    // blocking this will prevent conversation replying
    public func onAudioOutStart(callback: @escaping (String) -> Bool?) {
        eventHandlers.onAudioOutStart = callback
    }
    public func onAudioOutEnd(callback: @escaping () -> Void) {
        eventHandlers.onAudioOutEnd = callback
    }

    // TS: onFocusChanged(previousName, nextName)
    public func onFocusChanged(callback: @escaping (_ previousName: String, _ nextName: String) -> Bool?) {
        eventHandlers.onFocusChanged = callback
    }

    // TS: onFieldValueChanged(fieldName, answer)
    public func onFieldValueChanged(callback: @escaping (_ fieldName: String, _ answer: Any) -> Void) {
        eventHandlers.onFieldValueChanged = callback
    }

    // Backwards compatible aliases
    public func onFieldChanged(callback: @escaping (_ previous: ConversationStateEntry, _ next: ConversationStateEntry) -> Bool?) {
        eventHandlers.onFieldChanged = callback
    }
    public func onComplete(callback: @escaping (ConversationState) -> Void) {
        eventHandlers.onComplete = callback
    }

    public func onListening(callback: @escaping () -> Void) {
        eventHandlers.onListening = callback
    }
    public func onSpeaking(callback: @escaping () -> Void) {
        eventHandlers.onSpeaking = callback
    }

    public func onError(callback: @escaping (String) -> Void) {
        eventHandlers.onError = callback
    }
    public func onCriticalError(callback: @escaping (String) -> Void) {
        eventHandlers.onCriticalError = callback
    }

    private enum LogType {
        case error
        case warn
        case debug
    }

    private func log(_ message: String, type: LogType) {
        if type == .debug && !debug && !verbose {
            return
        }
        print("Veform: \(message)")
    }

    // iOS has no DOM audio element; this validates required privacy keys before startup.
    private func createAudioElement() {
        let micKey = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription")
        if micKey == nil {
            fatalError("veform: Missing NSMicrophoneUsageDescription in your app's Info.plist")
        }
    }

    private func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { microphoneGranted in
                DispatchQueue.main.async {
                    continuation.resume(returning: microphoneGranted)
                }
            }
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord,
                                         mode: .voiceChat,
                                         options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            VeConfig.vePrint("Veform: Audio session configured successfully")
        } catch {
            eventHandlers.error(error: "Failed to configure audio session: \(error.localizedDescription)")
            log("Failed to configure audio session: \(error)", type: .error)
        }
    }

    private func listenForMessages() {
        wsConnection?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.log("WS message received", type: .debug)
                    self.handleWebSocketMessage(text)
                case .data(let data):
                    self.log("WS received unexpected binary payload (\(data.count) bytes)", type: .warn)
                @unknown default:
                    self.log("WS message received (unknown type)", type: .warn)
                }
                self.listenForMessages()
            case .failure(let error):
                self.log("WS error: \(error)", type: .error)
                self.eventHandlers.error(error: "WebSocket error: \(error.localizedDescription)")
                self.stop()
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            log("WS message failed UTF-8 decoding", type: .error)
            return
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            log("WS message is not valid JSON object", type: .error)
            return
        }

        let payload = json["payload"] as? [String: Any]
        switch type {
        case "turn-credentials":
            guard let payload, let iceServers = payload["iceServers"] as? [[String: Any]] else {
                log("turn-credentials missing iceServers payload", type: .error)
                return
            }
            if peerConnection == nil {
                setupPeerConnection(iceServers: iceServers)
            }
        case "answer":
            guard let payload else {
                log("answer missing payload", type: .error)
                return
            }
            applyRemoteAnswer(payload: payload)
        case "ice-candidate":
            guard let payload else {
                log("ice-candidate missing payload", type: .error)
                return
            }
            applyRemoteIceCandidate(payload: payload)
        default:
            // Event message parsing/handling will be added later.
            break
        }
    }

    private func setupPeerConnection(iceServers: [[String: Any]]) {
        let rtcIceServers: [RTCIceServer] = iceServers.compactMap { server in
            let urlsValue = server["urls"]
            let urls: [String]
            if let str = urlsValue as? String {
                urls = [str]
            } else if let arr = urlsValue as? [String] {
                urls = arr
            } else {
                return nil
            }
            let username = server["username"] as? String
            let credential = server["credential"] as? String
            return RTCIceServer(urlStrings: urls, username: username, credential: credential)
        }

        let config = RTCConfiguration()
        config.iceServers = rtcIceServers
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        let factory = RTCPeerConnectionFactory()
        peerConnectionFactory = factory
        let peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: nil)
        self.peerConnection = peerConnection

        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "googEchoCancellation": "true",
                "googAutoGainControl": "true",
                "googNoiseSuppression": "true",
                "googHighpassFilter": "true"
            ],
            optionalConstraints: nil
        )
        let audioSource = factory.audioSource(with: audioConstraints)
        let localAudioTrack = factory.audioTrack(with: audioSource, trackId: "local_audio")
        peerConnection.add(localAudioTrack, streamIds: ["local_stream"])

        peerConnection.onIceCandidate = { [weak self] candidate in
            guard let self, let candidate else { return }
            self.log("RTC: Sending candidate to server", type: .debug)
            self.sendWebSocketJSON([
                "type": "ice-candidate",
                "payload": [
                    "candidate": candidate.sdp,
                    "sdpMid": candidate.sdpMid as Any,
                    "sdpMLineIndex": candidate.sdpMLineIndex
                ]
            ])
        }

        createAndSendOffer()
    }

    private func createAndSendOffer() {
        guard let peerConnection else {
            log("Peer connection is not ready", type: .error)
            return
        }

        let offerConstraints = RTCMediaConstraints(mandatoryConstraints: ["levelControl": "true"], optionalConstraints: nil)
        peerConnection.offer(for: offerConstraints) { [weak self] offer, error in
            guard let self else { return }
            if let error {
                self.log("RTC: Failed to create offer \(error)", type: .error)
                return
            }
            guard let offer else {
                self.log("RTC: Offer was nil", type: .error)
                return
            }

            peerConnection.setLocalDescription(offer) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.log("RTC: Failed to set local description \(error)", type: .error)
                    return
                }

                self.log("RTC: Sending offer to server", type: .debug)
                self.sendWebSocketJSON([
                    "type": "offer",
                    "payload": [
                        "type": offer.type.rawValue,
                        "sdp": offer.sdp
                    ]
                ])

                if let form = self.form {
                    self.log("RTC: Sending form to server", type: .debug)
                    self.sendForm(form)
                }
            }
        }
    }

    private func applyRemoteAnswer(payload: [String: Any]) {
        guard let peerConnection else {
            log("RTC: Received answer before peer connection setup", type: .error)
            return
        }
        guard
            let sdp = payload["sdp"] as? String,
            let typeString = payload["type"] as? String,
            let type = RTCSdpType.fromString(typeString)
        else {
            log("RTC: Invalid answer payload", type: .error)
            return
        }

        let remoteDescription = RTCSessionDescription(type: type, sdp: sdp)
        peerConnection.setRemoteDescription(remoteDescription) { [weak self] error in
            if let error {
                self?.log("RTC: Failed to set remote answer \(error)", type: .error)
                return
            }
            self?.log("RTC: Remote answer applied", type: .debug)
            self?.eventHandlers.runningStarted()
        }
    }

    private func applyRemoteIceCandidate(payload: [String: Any]) {
        guard let peerConnection else {
            log("RTC: Received candidate before peer connection setup", type: .error)
            return
        }
        guard
            let candidateSdp = payload["candidate"] as? String,
            let sdpMLineIndexAny = payload["sdpMLineIndex"],
            let sdpMLineIndex = asInt32(sdpMLineIndexAny)
        else {
            log("RTC: Invalid ice-candidate payload", type: .error)
            return
        }

        let sdpMid = payload["sdpMid"] as? String
        let candidate = RTCIceCandidate(sdp: candidateSdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection.add(candidate) { [weak self] error in
            if let error {
                self?.log("RTC: Failed to add remote candidate \(error)", type: .error)
                return
            }
            self?.log("RTC: Remote candidate added", type: .debug)
        }
    }

    private func sendForm(_ form: Form) {
        guard let formData = try? JSONEncoder().encode(form),
              let formObject = try? JSONSerialization.jsonObject(with: formData)
        else {
            log("Failed to encode form payload", type: .error)
            return
        }

        sendWebSocketJSON([
            "type": "form",
            "payload": formObject
        ])
    }

    private func sendWebSocketJSON(_ payload: [String: Any]) {
        guard let wsConnection else {
            log("WS connection not available for send", type: .error)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else {
            log("Failed to serialize websocket payload", type: .error)
            return
        }

        wsConnection.send(.string(text)) { [weak self] error in
            if let error {
                self?.log("WS send failed: \(error)", type: .error)
            }
        }
    }

    private func asInt32(_ value: Any) -> Int32? {
        if let intValue = value as? Int {
            return Int32(intValue)
        }
        if let int32Value = value as? Int32 {
            return int32Value
        }
        if let doubleValue = value as? Double {
            return Int32(doubleValue)
        }
        return nil
    }
}

private extension RTCSdpType {
    static func fromString(_ value: String) -> RTCSdpType? {
        switch value.lowercased() {
        case "offer":
            return .offer
        case "pranswer":
            return .prAnswer
        case "answer":
            return .answer
        case "rollback":
            return .rollback
        default:
            return nil
        }
    }
}


public class VeformEventHandlers {
    var onLoadingStarted: (() -> Void)?
    var onLoadingFinished: (() -> Void)?
    var onRunningStarted: (() -> Void)?
    var onRunningFinished: (() -> Void)?
    var onAudioInStart: (() -> Void)?
    var onAudioInChunk: ((String) -> Void)?
    var onAudioInEnd: ((String) -> Bool?)?
    var onAudioOutStart: ((String) -> Bool?)?
    var onFieldChanged: ((_ previous: ConversationStateEntry, _ next: ConversationStateEntry) -> Bool?)?
    var onAudioOutEnd: (() -> Void)?
    var onListening: (() -> Void)?
    var onSpeaking: (() -> Void)?
    var onError: ((String) -> Void)?
    var onCriticalError: ((String) -> Void)?
    var onFinished: (() -> Void)?
    var onFocusChanged: ((_ previousName: String, _ nextName: String) -> Bool?)?
    var onFieldValueChanged: ((_ fieldName: String, _ answer: Any) -> Void)?
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
        Veform.running = false
        if let handler = onRunningFinished {
            DispatchQueue.main.async {
                handler()
            }
        }
        if let handler = onFinished {
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
    
    func audioInEnd(_ data: String) -> Bool? {
        if let handler = onAudioInEnd {
            return handler(data)
        }
        return false
    }
    
    func audioOutStart(_ data: String) -> Bool? {
        if let handler = onAudioOutStart {
            return handler(data)
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
        if let focusHandler = onFocusChanged {
            return focusHandler(previous.name, next.name)
        }
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
    func criticalError(error: String) {
        if let handler = onCriticalError {
            DispatchQueue.main.async {
                handler(error)
            }
            return
        }
    }
}

public func isRunning() -> Bool {
    return Veform.running
}
