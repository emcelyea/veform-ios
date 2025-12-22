import Foundation


 
let genReplyStartFlag = "*START*"
let genReplyEndFlag = "*END*"
class VeConversation {
    var form: Form
    var genReply: GenReply

    private var emitEvent: ((ConversationEvent, String?) -> Void) = { _, _ in }
    private var onComplete: (ConversationState) -> Void

    private let punctuationCharacters = [".", "!", "?", ";"]
    private var currentFieldName: String
    private var initialFieldName: String
    private var fieldState: [String: FieldState] = [:]
    private var visitHistory: [FieldState] = []
    private var fieldHistory: [FieldHistory] = []

    private var genReplyMessageQueue: [WebSocketServerMessage] = []
    private var isProcessingGenReply: Bool = false

    init(
        form: Form,
        emitEvent: @escaping (ConversationEvent, String?) -> Void,
        onComplete: @escaping (ConversationState) -> Void
    ) {
        self.form = form
        self.emitEvent = emitEvent
        self.onComplete = onComplete
        genReply = GenReply(form: form)
        initialFieldName = self.form.fields[0].name
        currentFieldName = self.form.fields[0].name
        for field in form.fields {
            fieldState[field.name] = FieldState(name: field.name, valid: false, visitCount: 0)
        }
        Task {
            VeConfig.vePrint("VECONVO: Setting up conversation websocket connection")
            do {
                try await genReply.start(onMessage: self.genReplyMessageReceived)
            } catch {
                VeConfig.vePrint("VECONVO: Error starting conversation websocket connection: \(error)")
                emitEvent(.error, "Error starting conversation websocket connection: \(error.localizedDescription)")
            }
            emitEvent(.websocketSetup, nil)
            VeConfig.vePrint("VECONVO: Websockets configured, session started")
        }
    }

    func start() {
        genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.setupForm, data: form)
        VeConfig.vePrint("VECONVO: Starting conversation")
        let initialQuestion: String = getFieldQuestion(fieldName: currentFieldName)
        VeConfig.vePrint("VECONVO: Initial question: \(initialQuestion)")
        emitEvent(.audioOutMessage, initialQuestion)
        let field = form.fields.first(where: { $0.name == currentFieldName })
        if field?.type == .info {
            fieldState[currentFieldName]?.valid = true
            moveToNextField()
        }
    }

    func stop() {
        genReply.tewyWebsockets?.closeConnection()
    }
    // FINISH VEAUDIO MOVE IN
    // BUILD OUR INTERNAL VECONVERSATION EVENT LOOP
    // BUILD EVENT EXPOSURE IN VEFORM AND ALLOW IT TO CANCEL VECONVO DEFAULT HANDLERS
    func inputReceived(input: String) {
        fieldState[currentFieldName]?.valid = false
        let field = form.fields.first(where: { $0.name == currentFieldName })
        guard let field = field else {
            VeConfig.vePrint("VECONVO: Error, field \(currentFieldName) not found")
            return
        }

        let rulesValidation = RulesValidation(input: input, field: field)
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
            fieldState[currentFieldName]?.textarea = input
        default:
            VeConfig.vePrint("VECONVO: Error, unknown field type \(field.name))")
        }
         
        addCurrentFieldToFieldHistory(input: input, genReply: nil)

        if fieldState[currentFieldName]?.valid == true {
            let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
            emitEvent(.audioOutMessage, nextOutput)
            moveToNextField()
            return
        }

        emitEvent(.pauseListening, nil)
        fieldState[currentFieldName]?.hotPhraseSkipResolved = false
        fieldState[currentFieldName]?.hotPhraseLastResolved = false
        fieldState[currentFieldName]?.hotPhraseEndResolved = false
        fieldState[currentFieldName]?.hotPhraseMoveToResolved = false
        genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.hotPhraseRequest, data: HotPhraseRequest(fieldName: currentFieldName, question: field.question, input: input))
        let fieldHistory = fieldHistory.filter { $0.name == currentFieldName }
        print("VECONVO CHECKING GEN START, \(field.validation.validate) \(field.type)")
        if field.validation.validate == true || field.type != .textarea {
            fieldState[currentFieldName]?.genReplyRunning = true
            genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.genReplyRequest, data: GenReplyRequest(fieldName: currentFieldName, fieldHistory: fieldHistory))
        }
        // output thinking message to cover time before responses come back
        let nextOutput = outputsThinking.randomElement() ?? ""
        emitEvent(.audioOutMessage, nextOutput)
    }

    private func moveToNextField(input: String? = nil, noVisit: Bool = false, traversing: Bool = false) {
        if fieldState[currentFieldName]?.valid == true || fieldState[currentFieldName]?
            .skip == true || fieldState[currentFieldName]?.last == true || fieldState[currentFieldName]?
            .end == true || fieldState[currentFieldName]?.moveToName != nil
        {
            guard let nextField = getNextField(fieldName: currentFieldName) else {
                endForm()
                return
            }

            if !noVisit {
                addCurrentFieldToVisitHistory()
                addCurrentFieldToFieldHistory(input: input, genReply: nil)
                fieldState[currentFieldName]?.visitCount += 1
            }
            let field = form.fields.first(where: { $0.name == nextField.name })
            guard let field = field else {
                VeConfig.vePrint("VECONVO: Error, tried to move to fieldId \(nextField.name) but it doesn't exist")
                return
            }
            VeConfig.vePrint("VECONVO: Moving to fieldName: \(nextField.name) \(field.question)")
            fieldState[currentFieldName]?.skip = false
            fieldState[currentFieldName]?.last = false
            fieldState[currentFieldName]?.end = false
            fieldState[currentFieldName]?.moveToName = nil
            currentFieldName = nextField.name
            if fieldState[nextField.name]?.valid == true, traversing == true {
                return moveToNextField(noVisit: true, traversing: true)
            }
            // we gotta dispatch rest of events, events for the most part are gonna be for
            // consumers to hook into rather than for us to handle
            emitEvent(.fieldChanged, currentFieldName)
            let nextQuestion = getFieldQuestion(fieldName: nextField.name)
            emitEvent(.audioOutMessage, nextQuestion)
            if field.type == .info {
                fieldState[nextField.name]?.valid = true
                moveToNextField()
            }
        } else {
            VeConfig.vePrint("VECONVO: moveToNextField called with invalid field: \(currentFieldName)")
        }
    }

    private func getNextField(fieldName: String) -> Field? {
        if let fieldState = fieldState[fieldName] {
            return getNextFieldFromFieldState(currentFieldState: fieldState, form: form, visitHistory: visitHistory)
        }
        return nil
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
            emitEvent(.audioOutMessage, message.data ?? "")
            isProcessingGenReply = false
            processNextGenReplyMessage()
            return
        }

        let newState = updateStateFromMessage(message: message, field: field, fieldState: state)
        fieldState[message.fieldName ?? ""] = newState
        // field in a state where we can move on
        if newState.skip == true, 
        newState.last == true, 
        newState.end == true, 
        newState.moveToName != nil ||
        (allHotPhrasesResolved(fieldState: newState) && newState.valid == true) {
            let output = message.data ?? getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
            emitEvent(.audioOutMessage, output)
            emitEvent(.resumeListening, nil)
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

    func getFieldStateEntry(name: String) -> ConversationStateEntry? {
        let field = form.fields.first(where: { $0.name == name })
        guard let field = field else {
            return nil
        }
        let answer = getAnswerFromFieldState(fieldState: fieldState[name]!, field: field)
        return ConversationStateEntry(
            name: name,
            question: field.question,
            answer: answer,
            type: field.type,
            valid: fieldState[name]?.valid ?? false
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
        onComplete(completeEntries)
    }

    private func moveToAnyIncompleteField(root: String?) -> Bool? {
        var fieldName = root
        var previousFieldName = root
        while let currentField = fieldName {
            if fieldState[currentField]?.valid == false {
                currentFieldName = previousFieldName ?? currentFieldName
                emitEvent(.audioOutMessage, "Looks like we have a required question we need to revisit")
                moveToNextField(noVisit: true, traversing: true)
                return true
            }
            previousFieldName = currentField
            fieldName = getNextField(fieldName: currentField)?.name
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
            fieldName = getNextField(fieldName: currentField)?.name
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


