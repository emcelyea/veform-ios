import Foundation


 
let genReplyStartFlag = "*START*"
let genReplyEndFlag = "*END*"
class VeConversation {
    var form: Form
    var genReply: GenReply

    private let punctuationCharacters = [".", "!", "?", ";"]
    private var currentFieldName: String
    private var initialFieldName: String
    private var fieldState: [String: FieldState] = [:]
    private var visitHistory: [FieldState] = []
    private var fieldHistory: [FieldHistory] = []
    private var audio: VeAudio!
    private var audioEventHandlers: VeAudioEventHandlers
    private weak var eventHandlers: VeformEventHandlers?

    private var genReplyMessageQueue: [WebSocketServerMessage] = []
    private var isProcessingGenReply: Bool = false

    init(
        form: Form,
        eventHandlers: VeformEventHandlers
    ) {
        // NEXT TIME CLEAR UP THESE AUDIO EVENT HANDLER PASSINGS UR ALL CONFUSED AND 
        // STUPID LOL
        print("VECONVO: Initializing conversation")
        self.form = form
        self.eventHandlers = eventHandlers
        self.audioEventHandlers = VeAudioEventHandlers()

        eventHandlers.loadingStarted()
        genReply = GenReply(form: form)
        initialFieldName = self.form.fields[0].name
        currentFieldName = self.form.fields[0].name
        for field in form.fields {
            fieldState[field.name] = FieldState(name: field.name, valid: false, visitCount: 0)
        }
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
                try await genReply.start(onMessage: self.genReplyMessageReceived)
                print("VECONVO: finished our await stuff")
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
        VeConfig.vePrint("VECONVO: Starting conversation")
        let field = form.fields.first(where: { $0.name == currentFieldName })
        guard let field = field else {
            VeConfig.vePrint("VECONVO: Error, field \(currentFieldName) not found")
            return
        }
        let initialQuestion: String = getFieldQuestion(field: field, fieldState: fieldState[currentFieldName]!)
        VeConfig.vePrint("VECONVO: Initial question: \(initialQuestion)")
        audio.output(initialQuestion)
        if field.type == .info {
            fieldState[currentFieldName]?.valid = true
            moveToNextField()
        }
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
        eventHandlers?.audioInEnd(data)
        // consumer intercepted event
        fieldState[currentFieldName]?.valid = false
        let field = form.fields.first(where: { $0.name == currentFieldName })
        guard let field = field else {
            VeConfig.vePrint("VECONVO: Error, field \(currentFieldName) not found")
            return
        }
        let rulesValidation = RulesValidation(input: data, field: field)
        switch field.type {
            case .yesNo:
                let yesNoReply = rulesValidation.validateYesNo()
                fieldState[currentFieldName]?.validYes = yesNoReply.answer == .yes ? true : false
                fieldState[currentFieldName]?.validNo = yesNoReply.answer == .no ? true : false
                fieldState[currentFieldName]?.valid = yesNoReply.valid
            case .select:
                let selectReply = rulesValidation.validateSelect()
                fieldState[currentFieldName]?.valid = selectReply.valid
                fieldState[currentFieldName]?.selectOption = selectReply.selectOption ?? nil
            case .multiselect:
                let multiselectReply = rulesValidation.validateMultiselect()
                fieldState[currentFieldName]?.valid = multiselectReply.valid
                fieldState[currentFieldName]?.selectOptions = multiselectReply.selectOptions ?? nil
            case .number:
                let numberReply = rulesValidation.validateNumber()
                fieldState[currentFieldName]?.valid = numberReply.valid
                fieldState[currentFieldName]?.number = numberReply.number
            case .textarea:
                fieldState[currentFieldName]?.textarea = data
            default:
                VeConfig.vePrint("VECONVO: Error, unknown field type \(field.name))")
        }
        addCurrentFieldToFieldHistory(input: data, genReply: nil)
        if fieldState[currentFieldName]?.valid == true {
            let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
            audio.output(nextOutput)
            moveToNextField()
            return
        }
        audio.pauseListening()
        let nextOutput = outputsThinking.randomElement() ?? ""
        audio.output(nextOutput)
        fieldState[currentFieldName]?.hotPhraseSkipResolved = false
        fieldState[currentFieldName]?.hotPhraseLastResolved = false
        fieldState[currentFieldName]?.hotPhraseEndResolved = false
        fieldState[currentFieldName]?.hotPhraseMoveToResolved = false
        genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.hotPhraseRequest, data: HotPhraseRequest(fieldName: currentFieldName, question: field.question, input: data))
        print("VECONVO CHECKING GEN START, \(field.validation.validate) \(field.type)")
        if field.validation.validate == true || field.type != .textarea {
            fieldState[currentFieldName]?.genReplyRunning = true
            let fieldHistory = fieldHistory.filter { $0.name == currentFieldName }
            genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.genReplyRequest, data: GenReplyRequest(fieldName: currentFieldName, fieldHistory: fieldHistory))
        }
    }
    func onAudioOutStart(_ data: String) -> Bool? {
        return eventHandlers?.audioOutStart(data)
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
  
    private func moveToNextField(noVisit: Bool = false, traversing: Bool = false) {
        let currentFieldState = fieldState[currentFieldName]!
        if !noVisit {
            addCurrentFieldToVisitHistory()
            addCurrentFieldToFieldHistory(input: nil, genReply: nil)
            fieldState[currentFieldName]?.visitCount += 1
        }
        guard let nextField = getNextFieldFromFieldState(currentFieldState: currentFieldState, form: form, visitHistory: visitHistory) else {
            endForm()
            return
        }
        fieldState[currentFieldName]?.skip = false
        fieldState[currentFieldName]?.last = false
        fieldState[currentFieldName]?.end = false
        fieldState[currentFieldName]?.moveToName = nil
        currentFieldName = nextField.name
        if fieldState[nextField.name]?.valid == true, traversing == true {
            return moveToNextField(noVisit: true, traversing: true)
        }
        let previousFieldState = fieldStateToConversationState(fieldState: currentFieldState)
        let nextFieldState = fieldStateToConversationState(fieldState: fieldState[nextField.name]!)
        guard let previousFieldState = previousFieldState, let nextFieldState = nextFieldState else {
            VeConfig.vePrint("Could not find fields to mvoe between \(currentFieldState.name) \(nextField.name)")
            return
        }
        let clientBlock = eventHandlers?.fieldChanged(previous:previousFieldState, next:nextFieldState)
        if clientBlock == true { return }
        let nextQuestion = getFieldQuestion(field: nextField, fieldState: fieldState[nextField.name]!)
        audio.output(nextQuestion)
        if nextField.type == .info {
            fieldState[nextField.name]?.valid = true
            moveToNextField()
        }
    }

    private func allHotPhrasesResolved(fieldState: FieldState) -> Bool {
        return fieldState.hotPhraseSkipResolved == true && fieldState.hotPhraseLastResolved == true && fieldState.hotPhraseEndResolved == true && fieldState.hotPhraseMoveToResolved == true
    }

    private func genReplyMessageReceived(message: WebSocketServerMessage) {
        genReplyMessageQueue.append(message)
        processNextGenReplyMessage()
    }

    private func processNextGenReplyMessage() {
        guard !isProcessingGenReply, !genReplyMessageQueue.isEmpty else { return }

        isProcessingGenReply = true
        let message = genReplyMessageQueue.removeFirst()
        // abort if field !exists      
        guard let field = form.fields.first(where: { $0.name == message.fieldName }), let state = fieldState[message.fieldName ?? ""] else {
            VeConfig.vePrint("VECONVO: Error, field \(message.fieldName) not found")
            isProcessingGenReply = false
            processNextGenReplyMessage()
            return
        }

        // abort if message is !for currentField
        if message.fieldName != currentFieldName {
            VeConfig.vePrint("VECONVO: Message is for a different field: \(message.fieldName) \(currentFieldName)")
            isProcessingGenReply = false
            processNextGenReplyMessage()
            return
        }

        // abort moveTo if name got !exist
        if message.type == SERVER_TO_CLIENT_MESSAGES.hotPhraseMoveTo {
            if let moveToName = message.moveToName {
                let moveToField = form.fields.first(where: { $0.name == moveToName })
                if moveToField == nil {
                    VeConfig.vePrint("VECONVO: Error, move to field \(moveToName) not found")
                    fieldState[currentFieldName]?.hotPhraseMoveToResolved = true
                    isProcessingGenReply = false
                    processNextGenReplyMessage()
                    return
                }
            }
        }

        if message.type == SERVER_TO_CLIENT_MESSAGES.genReplyChunk {
            VeConfig.vePrint("VECONVO: Outputting Gen sentence: \(message.data ?? "No data")")
            audio.output(message.data ?? "")
            isProcessingGenReply = false
            processNextGenReplyMessage()
            return
        }

        let newState = updateStateFromMessage(message: message, field: field, fieldState: state)
        fieldState[message.fieldName ?? ""] = newState
        print("VECONVO: State after genREply updates: \(newState)")
        print("VECONVO: testing allHotPhrasesResolved: \(allHotPhrasesResolved(fieldState: newState))")
        // field in a state where we can move on
        if newState.skip == true, 
        newState.last == true, 
        newState.end == true, 
        newState.moveToName != nil ||
        (allHotPhrasesResolved(fieldState: newState) && newState.valid == true) {
            let output = message.data ?? getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
            audio.output(output)
            audio.resumeListening()
            moveToNextField()
            isProcessingGenReply = false
            processNextGenReplyMessage()
            return
        }
        isProcessingGenReply = false
        processNextGenReplyMessage()
    }

    private func addCurrentFieldToFieldHistory(input: String?, genReply: String?) {
        let field = form.fields.first(where: { $0.name == currentFieldName })
        fieldHistory.append(FieldHistory(
            name: fieldState[currentFieldName]!.name,
            type: field?.type ?? .textarea,
            valid: fieldState[currentFieldName]!.valid,
            answer: input,
            genReply: genReply
        ))
    }

    private func addCurrentFieldToVisitHistory() {
        visitHistory.append(FieldState(
            name: fieldState[currentFieldName]!.name,
            valid: fieldState[currentFieldName]!.valid,
            visitCount: fieldState[currentFieldName]!.visitCount,
            validYes: fieldState[currentFieldName]!.validYes,
            validNo: fieldState[currentFieldName]!.validNo,
            selectOption: fieldState[currentFieldName]!.selectOption,
            skip: fieldState[currentFieldName]!.skip,
            last: fieldState[currentFieldName]!.last,
            end: fieldState[currentFieldName]!.end,
            moveToName: fieldState[currentFieldName]!.moveToName
        ))
    }

  func setCurrentField(name: String) {
        let field = form.fields.first(where: { $0.name == name })
        if field == nil {
            VeConfig.vePrint("VECONVO: Error, field \(name) not found")
            return
        }
        fieldState[currentFieldName]?.moveToName = name
        moveToNextField()
    }

    func getCurrentField() -> Field? {
        return form.fields.first(where: { $0.name == currentFieldName })
    }

    func fieldStateToConversationState(fieldState: FieldState) -> ConversationStateEntry? {
        let field = form.fields.first(where: { $0.name == fieldState.name })
        guard let field = field else {
            return nil
        }
        let answer = getAnswerFromFieldState(fieldState: fieldState, field: field)
        return ConversationStateEntry(
            name: fieldState.name,
            question: field.question,
            answer: answer,
            type: field.type,
            valid: fieldState.valid ?? false
        )
    }



    private func endForm() {
        addCurrentFieldToVisitHistory()
        // if we say moveTo
        VeConfig.vePrint("VECONVO: Testing incomplete fields")
        if moveToAnyIncompleteField(root: initialFieldName) != nil {
            return
        }
        let completeEntries = buildCompletedConversation()
        eventHandlers?.complete(conversationState: completeEntries)
    }

    private func moveToAnyIncompleteField(root: String?) -> Bool? {
        var fieldName = root
        var previousFieldName = root
        while let currentField = fieldName {
            if fieldState[currentField]?.valid == false {
                currentFieldName = previousFieldName ?? currentFieldName
                audio.output("Looks like we have a required question we need to revisit")
                moveToNextField(noVisit: true, traversing: true)
                return true
            }
            previousFieldName = currentField
            let nextField = getNextFieldFromFieldState(currentFieldState: fieldState[currentField]!, form: form, visitHistory: visitHistory)
            fieldName = nextField?.name
        }
        return nil
    }

    private func buildCompletedConversation() -> ConversationState {
        // start at initialField
        var fieldName: String? = initialFieldName
        var completeEntries: [ConversationStateEntry] = []
        while let currentField = fieldName {
            let field = form.fields.first(where: { $0.name == currentField })
            if field?.type != .info {
                let answer = getAnswerFromFieldState(fieldState: fieldState[currentField]!, field: field!)
                completeEntries.append(ConversationStateEntry(
                    name: currentField,
                    question: field?.question ?? "",
                    answer: answer,
                    type: field?.type ?? .textarea,
                    valid: true
                ))
            }
            let nextField = getNextFieldFromFieldState(currentFieldState: fieldState[currentField]!, form: form, visitHistory: visitHistory)
            fieldName = nextField?.name

        }
        return completeEntries
    }

    private func getConversationState() -> ConversationState {
        var conversationState: ConversationState = []
        for field in form.fields {
            let answer = getAnswerFromFieldState(fieldState: fieldState[field.name]!, field: field)
            conversationState.append(ConversationStateEntry(
                name: field.name,
                question: field.question,
                answer: answer,
                type: field.type,
                valid: fieldState[field.name]!.valid
            ))
        }
        return conversationState
    }

    func setFieldState(name: String, state: ConversationStateEntry) {
        let field = form.fields.first(where: { $0.name == name })
        guard let field = field else {
            VeConfig.vePrint("VECONVO: Error, field \(name) not found")
            return
        }
        fieldState[name] = fieldStateFromConversationState(field: field, state: state)
    }
}


