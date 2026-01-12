import Foundation

// TMRWWWWW
// we uhhh, like this is getting close
// lets start by just like, catching the initial form stuff and sending the question mp3 to the user
// we also need to write all the question mp3s on init so they exist, and then clean them up when session is over

class VeConversation {
    var form: Form
    var genReply: GenReply
    private var audio: VeAudio!
    private var audioEventHandlers: VeAudioEventHandlers
    private weak var eventHandlers: VeformEventHandlers?

    private var genReplyMessageQueue: [WebSocketServerMessage] = []
    private var isProcessingGenReply: Bool = false
    private var nextAudioOutContent: String?
    init(
        form: Form,
        eventHandlers: VeformEventHandlers
    ) {
        print("VECONVO: Initializing conversation")
        self.form = form
        self.eventHandlers = eventHandlers
        self.audioEventHandlers = VeAudioEventHandlers()

        eventHandlers.loadingStarted()
        genReply = GenReply(form: form)
        self.audioEventHandlers.onAudioInStart = self.onAudioInStart
        self.audioEventHandlers.onAudioInChunk = self.onAudioInChunk
        self.audioEventHandlers.onAudioInEnd = self.onAudioInEnd
        self.audioEventHandlers.onAudioOutStart = self.onAudioOutStart
        self.audioEventHandlers.onAudioOutEnd = self.onAudioOutEnd
        self.audioEventHandlers.onListening = self.onListening
        self.audioEventHandlers.onSpeaking = self.onSpeaking
        Task {
            VeConfig.vePrint("VECONVO: Setting up conversation websocket connection")
            do {
                audio = await VeAudio(eventHandlers: self.audioEventHandlers)
                try await genReply.start(onMessage: self.genReplyMessageReceived, onAudioBuffer: self.onAudioBuffer)
            } catch {
                VeConfig.vePrint("VECONVO: Error starting conversation websocket connection: \(error)")
                eventHandlers.error(error: "Error starting conversation websocket connection: \(error.localizedDescription)")
            }
            VeConfig.vePrint("VECONVO: Websockets configured, session started")
            eventHandlers.loadingFinished()
            self.start()
        }
    }

    func start() {
        genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.setupForm, data: form)
    }

    func stop() {
        genReply.tewyWebsockets?.closeConnection()
        audio.stop()
    }

    func onAudioInStart() {
        eventHandlers?.audioInStart()
    }
    
    func onAudioInChunk(_ data: String) {
       eventHandlers?.audioInChunk(data)
    }

    func onAudioInEnd(_ data: String) {
        let clientBlock = eventHandlers?.audioInEnd(data)
        if clientBlock == true { return }
        genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.audioInput, data: data)
    }
    
    func onAudioOutStart(_ data: String) -> Bool? {
        if nextAudioOutContent != nil {
            let abort = eventHandlers?.audioOutStart(nextAudioOutContent!)
            nextAudioOutContent = nil
            return abort
        }
        return nil
    }
    func onAudioOutEnd() -> Void {
        eventHandlers?.audioOutEnd()
    }
    func onListening() {
        eventHandlers?.listening()
    }
    func onSpeaking() {
        eventHandlers?.speaking()
    }
  
    private func genReplyMessageReceived(message: WebSocketServerMessage) {
        genReplyMessageQueue.append(message)
        processNextGenReplyMessage()
    }

    private func processNextGenReplyMessage() {
        guard !isProcessingGenReply, !genReplyMessageQueue.isEmpty else { return }

        isProcessingGenReply = true
        let message = genReplyMessageQueue.removeFirst()
        if message.type == .nextMessageAudio {
            nextAudioOutContent = message.data
            return
        }
        isProcessingGenReply = false
        processNextGenReplyMessage()
    }

    private func onAudioBuffer(buffer: Data) {
        print("VECONVO: HANDLING BUFFER")
        do {
            try audio.outputBuffer(buffer)
        } catch {
            VeConfig.vePrint("VECONVO: Error outputting audio buffer: \(error)")
        }
    }

    // func setCurrentField(name: String) {
    //     let field = form.fields.first(where: { $0.name == name })
    //     if field == nil {
    //         VeConfig.vePrint("VECONVO: Error, field \(name) not found")
    //         return
    //     }
    //     fieldState[currentFieldName]?.moveToName = name
    //     moveToNextField()
    // }

    // func getCurrentField() -> Field? {
    //     return form.fields.first(where: { $0.name == currentFieldName })
    // }

    // func fieldStateToConversationState(fieldState: FieldState) -> ConversationStateEntry? {
    //     let field = form.fields.first(where: { $0.name == fieldState.name })
    //     guard let field = field else {
    //         return nil
    //     }
    //     let answer = getAnswerFromFieldState(fieldState: fieldState, field: field)
    //     return ConversationStateEntry(
    //         name: fieldState.name,
    //         question: field.question,
    //         answer: answer,
    //         type: field.type,
    //         valid: fieldState.valid ?? false
    //     )
    // }



    // // private func endForm() {
    // //     addCurrentFieldToVisitHistory()
    // //     // if we say moveTo
    // //     VeConfig.vePrint("VECONVO: Testing incomplete fields")
    // //     if moveToAnyIncompleteField(root: initialFieldName) != nil {
    // //         return
    // //     }
    // //     let completeEntries = buildCompletedConversation()
    // //     eventHandlers?.complete(conversationState: completeEntries)
    // // }

    // // private func moveToAnyIncompleteField(root: String?) -> Bool? {
    // //     var fieldName = root
    // //     var previousFieldName = root
    // //     while let currentField = fieldName {
    // //         if fieldState[currentField]?.valid == false {
    // //             currentFieldName = previousFieldName ?? currentFieldName
    // //             audio.output("Looks like we have a required question we need to revisit")
    // //             moveToNextField(noVisit: true, traversing: true)
    // //             return true
    // //         }
    // //         previousFieldName = currentField
    // //         let nextField = getNextFieldFromFieldState(currentFieldState: fieldState[currentField]!, form: form, visitHistory: visitHistory)
    // //         fieldName = nextField?.name
    // //     }
    // //     return nil
    // // }

    // // private func buildCompletedConversation() -> ConversationState {
    // //     // start at initialField
    // //     var fieldName: String? = initialFieldName
    // //     var completeEntries: [ConversationStateEntry] = []
    // //     while let currentField = fieldName {
    // //         let field = form.fields.first(where: { $0.name == currentField })
    // //         if field?.type != .info {
    // //             let answer = getAnswerFromFieldState(fieldState: fieldState[currentField]!, field: field!)
    // //             completeEntries.append(ConversationStateEntry(
    // //                 name: currentField,
    // //                 question: field?.question ?? "",
    // //                 answer: answer,
    // //                 type: field?.type ?? .textarea,
    // //                 valid: true
    // //             ))
    // //         }
    // //         let nextField = getNextFieldFromFieldState(currentFieldState: fieldState[currentField]!, form: form, visitHistory: visitHistory)
    // //         fieldName = nextField?.name

    // //     }
    // //     return completeEntries
    // // }

    // // private func getConversationState() -> ConversationState {
    // //     var conversationState: ConversationState = []
    // //     for field in form.fields {
    // //         let answer = getAnswerFromFieldState(fieldState: fieldState[field.name]!, field: field)
    // //         conversationState.append(ConversationStateEntry(
    // //             name: field.name,
    // //             question: field.question,
    // //             answer: answer,
    // //             type: field.type,
    // //             valid: fieldState[field.name]!.valid
    // //         ))
    // //     }
    // //     return conversationState
    // // }

    // // func setFieldState(name: String, state: ConversationStateEntry) {
    // //     let field = form.fields.first(where: { $0.name == name })
    // //     guard let field = field else {
    // //         VeConfig.vePrint("VECONVO: Error, field \(name) not found")
    // //         return
    // //     }
    // //     fieldState[name] = fieldStateFromConversationState(field: field, state: state)
    // // }
}


