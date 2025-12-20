//
//  Audio.swift
//  conversation-app
//
//  Created by Eric McElyea on 10/10/25.
//
// Functions in this class dont really guard against overrunning eachother
// they are dumb so manager should coordinate listening & speaking
import AVFoundation
import Combine
import Foundation
import Speech

class VeAudio: NSObject {
    private let audioEngine: AVAudioEngine = .init()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private let synthesizer = AVSpeechSynthesizer()
    private var silenceTimer: Timer?
    private var silenceTimeout: TimeInterval = 2
    private var lastTextChunkEndIndex: Int = 0
    private var lastTextMessageEndIndex: Int = 0
    private var emitEvent: ((ConversationEvent, String?) -> Void)?
    private var speechBuffer: String = ""
    private var isTapInstalled: Bool = false
    private var isSpeakingOutput: Bool = false
    private var isPausedListening: Bool = false
    private var preferredVoice: AVSpeechSynthesisVoice?
    private var stopAfterOutput: Bool = false
    private var blockOutput: Bool = false
    private var debug: Bool = false
    init(emitEvent: @escaping (ConversationEvent, String?) -> Void, debug: Bool = false) {
        self.emitEvent = emitEvent
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.debug = debug
        super.init()
        synthesizer.delegate = self
        lastTextChunkEndIndex = 0

        Task {
            checkPrivacyKeys()
            let permissionsGranted = await requestPermissions()

            if !permissionsGranted {
                let permissionError = NSError(
                    domain: "ConversationForm",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognition permissions denied"]
                )
            }
            let betterVoices = AVSpeechSynthesisVoice.speechVoices().filter {
                $0.quality == .enhanced || $0.quality == .premium
            }
            if betterVoices.count > 0 {
                if betterVoices.contains(where: { $0.name == "Karen" }) {
                    preferredVoice = betterVoices.first(where: { $0.name == "Karen" })
                } else if betterVoices.contains(where: { $0.name == "Samantha" }) {
                    preferredVoice = betterVoices.first(where: { $0.name == "Samantha" })
                } else {
                    preferredVoice = betterVoices[0]
                }
            }
            configureAudioSession()
            emitEvent(.audioSetup, nil)
            startListening()
        }
    }

    private func checkPrivacyKeys() {
        let speechKey = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription")
        let micKey = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription")
        
        if speechKey == nil {
            fatalError("veform: Missing NSSpeechRecognitionUsageDescription in your app's Info.plist")
        }
        if micKey == nil {
            fatalError("veform: Missing NSMicrophoneUsageDescription in your app's Info.plist")
        }
    }

    private func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            // First request speech recognition permission
            SFSpeechRecognizer.requestAuthorization { authStatus in
                switch authStatus {
                case .authorized:
                    // If speech recognition is authorized, request microphone permission
                    AVAudioApplication.requestRecordPermission { microphoneGranted in
                        DispatchQueue.main.async {
                            continuation.resume(returning: microphoneGranted)
                        }
                    }

                case .denied, .restricted, .notDetermined:
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }

                @unknown default:
                    DispatchQueue.main.async {
                        continuation.resume(returning: false)
                    }
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
            VeConfig.vePrint("VEAUDIO: Audio session configured successfully")
        } catch {
            VeConfig.vePrint("VEAUDIO: Failed to configure audio session: \(error)")
        }
    }

    func stop() {
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stopWhenDone() {
        stopListening()
        stopAfterOutput = true
        if !isSpeakingOutput {
            stopOutput()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func stopOutput() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    func pauseListening() {
        isPausedListening = true
    }
    func resumeListening() {
        isPausedListening = false
        if !isSpeakingOutput { emitEvent?(.listening, nil) }
    }
    func isPaused() -> Bool {
        return isPausedListening
    }
    func bufferOutput(_ text: String) {
        speechBuffer += text
    }

    func output(_ text: String, block: Bool? = nil, purge: Bool? = nil) {
        if blockOutput && !(purge ?? false) {
            return
        }
        if block ?? false {
            blockOutput = true
        }
        if isSpeakingOutput {
            if purge ?? false {
                synthesizer.stopSpeaking(at: .immediate)
                isSpeakingOutput = false
                blockOutput = block ?? false
                speechBuffer = ""
            } else {
                VeConfig.vePrint("VEAUDIO: Buffering output \(text)")
                bufferOutput(text)
                return
            }
        }
        isSpeakingOutput = true
        emitEvent?(.speaking, nil)
        let optimizedText = optimizeOutput(text: " " + text)
        let utterance = AVSpeechUtterance(string: optimizedText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        if let preferredVoice = preferredVoice {
            if let voice = AVSpeechSynthesisVoice(identifier: preferredVoice.identifier) {
                utterance.voice = voice
            }
        }
        synthesizer.speak(utterance)
    }

    func pauseOutput() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeakingOutput = false
        emitEvent?(.listening, nil)
    }
    func resumeOutput() {
        synthesizer.continueSpeaking()
        isSpeakingOutput = true
    }

    func startListening() {
        // Check permissions
        do {
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw NSError(
                    domain: "ConversationForm",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"]
                )
            }

            guard speechRecognizer?.isAvailable == true else {
                throw NSError(
                    domain: "ConversationForm",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available"]
                )
            }
            recognitionTask?.cancel()
            recognitionTask = nil

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                throw NSError(
                    domain: "ConversationForm",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create speech recognition request"]
                )
            }
            recognitionRequest.shouldReportPartialResults = true
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                if self.stopAfterOutput { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let nextChunk = String(text.dropFirst(self.lastTextChunkEndIndex))
                    self.lastTextChunkEndIndex += nextChunk.count
                    self.emitEvent?(.audioInChunk, nextChunk)
                    silenceTimer?.invalidate()
                    silenceTimer = nil
                    silenceTimer = Timer
                        .scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
                            let nextMessage = String(text.dropFirst(self?.lastTextMessageEndIndex ?? 0))
                            self?.lastTextMessageEndIndex += nextMessage.count
                            self?.emitEvent?(.audioInMessage, nextMessage)
                        }

                    if let error = error {
                        VeConfig.vePrint("VEAUDIO: Error: \(error)")
                        return
                    }
                }
            }
            try setupAudioTap()
        } catch {
            VeConfig.vePrint("VEAUDIO: Error setting up audio tap: \(error)")
        }
    }

    func setupAudioTap() throws {
        if !isTapInstalled {
            isTapInstalled = true
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                if self?.isSpeakingOutput == true || self?.isPausedListening == true { return }
                self?.recognitionRequest?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        }
    }

    private func optimizeOutput(text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmedText
        if let firstChar = result.first,
           String(firstChar).rangeOfCharacter(from: .punctuationCharacters) != nil
        {
            result = String(result.dropFirst())
        }
        return result
    }
}

extension VeAudio: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_: AVSpeechSynthesizer, didStart _: AVSpeechUtterance) {}

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        isSpeakingOutput = false
        blockOutput = false
        print("VEAUDIO: Speech synthesizer did finish")
        if speechBuffer.count > 0 {
            print("VEAUDIO: emitting contents of speechBuffer: \(speechBuffer)")
            output(speechBuffer)
            speechBuffer = ""
        } else {
            if stopAfterOutput {
                print("VEAUDIO: stoppingAfterOutput")
                stopOutput()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } else {
                print("VEAUDIO: not stoppingAfterOutput paused:\(isPausedListening)")
                if !isPausedListening { emitEvent?(.listening, nil) }
            }
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didPause _: AVSpeechUtterance) {}

    func speechSynthesizer(_: AVSpeechSynthesizer, didContinue _: AVSpeechUtterance) {}

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {}
}
