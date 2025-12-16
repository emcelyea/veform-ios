import Foundation
/*
TOMORROW READ THIS YOU FUCKING BLOCKHEAD MORON

*/
struct GenReplyRequest: Codable {
    let fieldName: String
    let fieldHistory: [FieldHistory]
}
struct FieldHistory: Codable {
    var name: String
    var type: FieldTypes
    var valid: Bool
    var answer: String?
    var genReply: String?
}
struct FieldState {
    var name: String
    var valid: Bool
    var visitCount: Int
    var validYes: Bool?
    var validNo: Bool?
    var number: Double?
    var selectOption: SelectOption?
    var selectOptions: [SelectOption]?
    var textarea: String?
    var skip: Bool?
    var last: Bool?
    var end: Bool?
    var moveToId: String?
    init(
        name: String,
        valid: Bool,
        visitCount: Int,
        validYes: Bool? = nil,
        validNo: Bool? = nil,
        selectOption: SelectOption? = nil,
        skip: Bool? = nil,
        last: Bool? = nil,
        end: Bool? = nil,
        moveToId: String? = nil
    ) {
        self.name = name
        self.valid = valid
        self.visitCount = visitCount
        self.validYes = validYes
        self.validNo = validNo
        self.selectOption = selectOption
        self.skip = skip
        self.last = last
        self.end = end
        self.moveToId = moveToId
    }
}

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
            try await genReply.start(onMessage: self.genReplyMessageReceived)
            emitEvent(.websocketSetup, nil)
            VeConfig.vePrint("VECONVO: Websockets configured, session started")
        }
    }

    func start() {
        genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.setupForm, data: form)
        VeConfig.vePrint("VECONVO: Starting conversation")
        let initialQuestion: String = getFieldQuestion(fieldName: currentFieldName)
        let initialQuestionAppend: String = getFieldQuestionAppend(fieldName: currentFieldName)
        VeConfig.vePrint("VECONVO: Initial question: \(initialQuestion + initialQuestionAppend)")
        emitEvent(.audioOutMessage, initialQuestion + initialQuestionAppend)
        let field = form.fields.first(where: { $0.name == currentFieldName })
        if field?.type == .info {
            fieldState[currentFieldName]?.valid = true
            moveToNextField()
        }
    }

    func stop() {
        genReply.tewyWebsockets?.closeConnection()
    }

    func inputReceived(input: String) {
        fieldState[currentFieldName]?.valid = false
        let field = form.fields.first(where: { $0.name == currentFieldName })
        guard let field = field else {
            VeConfig.vePrint("VECONVO: Error, field \(currentFieldName) not found")
            return
        }

        switch field.type {
        // Info field really shouldn't ever be current when input is received
        case .yesNo:
            handleInputYesNoField(input: input, field: field)
        case .select:
            handleInputSelectField(input: input, field: field)
        case .multiselect:
            handleInputMultiselectField(input: input, field: field)
        case .textarea:
            handleInputTextareaField(input: input, field: field)
        case .number:
            handleInputNumberField(input: input, field: field)
        default:
            VeConfig.vePrint("VECONVO: Error, unknown field type \(field.name))")
        }
    }

    func setCurrentField(name: String) {
        let field = form.fields.first(where: { $0.name == name })
        if field == nil {
            VeConfig.vePrint("VECONVO: Error, field \(name) not found")
            return
        }
        fieldState[currentFieldName]?.moveToId = name
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

    func getConversationState() -> ConversationState {
        return buildFullConversationState()
    }

    func setFieldState(name: String, state: ConversationStateEntry) {
        let field = form.fields.first(where: { $0.name == name })
        guard let field = field else {
            VeConfig.vePrint("VECONVO: Error, field \(name) not found")
            return
        }
        fieldState[name] = FieldState(name: name, valid: state.valid, visitCount: fieldState[name]?.visitCount ?? 0)

        let answerString: String
        let answerDouble: Double?
        switch state.answer {
        case let .string(text):
            answerString = text
            answerDouble = Double(text)
        case let .double(number):
            answerString = String(number)
            answerDouble = number
        }
        if field.type == .yesNo {
            fieldState[name]?.validYes = answerString == "yes" ? true : false
            fieldState[name]?.validNo = answerString == "no" ? true : false
        } else if field.type == .select {
            let selectOption = field.validation.selectOptions?.first(where: { $0.value == answerString })
            fieldState[name]?.selectOption = selectOption
        } else if field.type == .multiselect {
            let selected = answerString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let selectOptions = field.validation.selectOptions?.filter { selected.contains($0.value) }
            fieldState[name]?.selectOptions = selectOptions
        } else if field.type == .textarea {
            fieldState[name]?.textarea = answerString
        } else if field.type == .number {
            fieldState[name]?.number = answerDouble
        }
    }

    private func handleInputYesNoField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldName]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldName]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldName]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldName]?.moveToId = hotPhraseReply.moveToId ?? nil

        let yesNoReply = rulesValidation.validateYesNo()
        fieldState[currentFieldName]?.validYes = yesNoReply.answer == .yes ? true : false
        fieldState[currentFieldName]?.validNo = yesNoReply.answer == .no ? true : false
        fieldState[currentFieldName]?.valid = yesNoReply.valid

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
        emitEvent(.audioOutMessage, nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputSelectField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldName]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldName]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldName]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldName]?.moveToId = hotPhraseReply.moveToId ?? nil

        let selectReply = rulesValidation.validateSelect()
        fieldState[currentFieldName]?.valid = selectReply.valid
        fieldState[currentFieldName]?.selectOption = selectReply.selectOption ?? nil

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
        emitEvent(.audioOutMessage, nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputMultiselectField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldName]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldName]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldName]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldName]?.moveToId = hotPhraseReply.moveToId ?? nil

        let multiselectReply = rulesValidation.validateMultiselect()
        fieldState[currentFieldName]?.valid = multiselectReply.valid
        fieldState[currentFieldName]?.selectOptions = multiselectReply.selectOptions ?? nil

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
        emitEvent(.audioOutMessage, nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputTextareaField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldName]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldName]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldName]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldName]?.textarea = input
        // we cant really validate a textarea with rules, so we just moveToNext to trigger llm
        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
        emitEvent(.audioOutMessage, nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputNumberField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldName]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldName]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldName]?.end = hotPhraseReply.end ?? false

        let numberReply = rulesValidation.validateNumber()
        fieldState[currentFieldName]?.valid = numberReply.valid
        fieldState[currentFieldName]?.number = numberReply.number

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldName]!)
        emitEvent(.audioOutMessage, nextOutput)
        moveToNextField(input: input)
    }

    private func endForm() {
        VeConfig.vePrint("VECONVO: Ending form")
        addCurrentFieldToVisitHistory()
        // if we say moveTo
        VeConfig.vePrint("VECONVO: Testing incomplete fields")
        if moveToAnyIncompleteField(root: initialFieldName) != nil {
            return
        }
        let completeEntries = buildCompletedConversation()
        onComplete(completeEntries)
    }

    private func moveToNextField(input: String? = nil, noVisit: Bool = false, traversing: Bool = false) {
        if fieldState[currentFieldName]?.valid == true || fieldState[currentFieldName]?
            .skip == true || fieldState[currentFieldName]?.last == true || fieldState[currentFieldName]?
            .end == true || fieldState[currentFieldName]?.moveToId != nil
        {
            guard let nextFieldName = getNextFieldName(fieldName: currentFieldName) else {
                endForm()
                return
            }

            if !noVisit {
                addCurrentFieldToVisitHistory()
                addCurrentFieldToFieldHistory(input: input, genReply: nil)
                fieldState[currentFieldName]?.visitCount += 1
            }
            let field = form.fields.first(where: { $0.name == nextFieldName })
            guard let field = field else {
                VeConfig.vePrint("VECONVO: Error, tried to move to fieldId \(nextFieldName) but it doesn't exist")
                return
            }
            VeConfig.vePrint("VECONVO: Moving to fieldName: \(nextFieldName) \(field.question)")
            fieldState[currentFieldName]?.skip = false
            fieldState[currentFieldName]?.last = false
            fieldState[currentFieldName]?.end = false
            fieldState[currentFieldName]?.moveToId = nil
            currentFieldName = nextFieldName
            if fieldState[nextFieldName]?.valid == true, traversing == true {
                return moveToNextField(noVisit: true, traversing: true)
            }
            emitEvent(.fieldChanged, currentFieldName)
            let nextQuestion = getFieldQuestion(fieldName: nextFieldName)
            let nextQuestionAppend: String = getFieldQuestionAppend(fieldName: nextFieldName)
            emitEvent(.audioOutMessage, nextQuestion + nextQuestionAppend)
            // if info immediately move on
            if field.type == .info {
                fieldState[nextFieldName]?.valid = true
                moveToNextField()
            }
        } else {
            if let input = input {
                addCurrentFieldToFieldHistory(input: input, genReply: nil)
                emitEvent(.genReplyRequestStart, nil)
                let fieldHistory = fieldHistory.filter { $0.name == currentFieldName }
                genReply.sendMessage(type: CLIENT_TO_SERVER_MESSAGES.genReplyRequest, data: GenReplyRequest(fieldName: currentFieldName, fieldHistory: fieldHistory))
            }
        }
    }

    // look at field and fieldState and resolve what string should be emitted
    private func getResponseOutput(field: Field, fieldState: FieldState) -> String {
        if fieldState.skip == true {
            let behaviorOutput = field.eventConfig[.eventSkipRequested]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return outputsAcknowledgeSkip.randomElement() ?? ""
        }

        if fieldState.last == true {
            if visitHistory.count == 0 {
                return "There is no last question to revisit, gonna repeat this one: \(field.question)"
            }

            let behaviorOutput = field.eventConfig[.eventLastRequested]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return outputsAcknowledgeLast.randomElement() ?? ""
        }

        if fieldState.end == true {
            let behaviorOutput = field.eventConfig[.eventEndRequested]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return outputsAcknowledgeEnd.randomElement() ?? ""
        }

        if fieldState.moveToId != nil {
            // TODO: moveto logic and events
            return outputsAcknowledgeSkip.randomElement() ?? ""
        }

        if fieldState.selectOption != nil {
            let behaviorOutput = fieldState.selectOption?.behaviors?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
        }

        if fieldState.valid == true {
            var hasBehaviorEnd = field.eventConfig[.eventValidAnswer]?.filter { $0.type == .behaviorEnd } ?? []

            if fieldState.validYes == true {
                let behaviorOutput = field.eventConfig[.eventValidYesAnswer]?
                    .filter { $0.type == .behaviorOutput } ?? []
                if behaviorOutput.count > 0 {
                    return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
                }
                hasBehaviorEnd = field.eventConfig[.eventValidYesAnswer]?.filter { $0.type == .behaviorEnd } ?? []
            }
            if fieldState.validNo == true {
                let behaviorOutput = field.eventConfig[.eventValidNoAnswer]?.filter { $0.type == .behaviorOutput } ?? []
                if behaviorOutput.count > 0 {
                    return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
                }
                hasBehaviorEnd = field.eventConfig[.eventValidNoAnswer]?.filter { $0.type == .behaviorEnd } ?? []
            }
            let behaviorOutput = field.eventConfig[.eventValidAnswer]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            if hasBehaviorEnd.count > 0 {
                return outputsAcknowledgeEnd.randomElement() ?? ""
            }
            return outputsAcknowledgeSuccess.randomElement() ?? ""
        }
        if fieldState.valid == false {
            let behaviorOutput = field.eventConfig[.eventInvalidAnswer]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return outputsThinking.randomElement() ?? ""
        }
        return outputsAcknowledgeSuccess.randomElement() ?? ""
    }

    private func getNextFieldName(fieldName: String) -> String? {
        let fieldState = fieldState[fieldName]
        let field = form.fields.first(where: { $0.name == fieldName })
        guard let field = field, let fieldState = fieldState else {
            VeConfig.vePrint("VECONVO: Error, field \(fieldName) not found")
            return nil
        }
        if fieldState.skip == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventSkipRequested] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldNames?.first
            }
            let currentFieldIndex = form.fields.firstIndex(where: { $0.name == currentFieldName })
            if let currentFieldIndex = currentFieldIndex, currentFieldIndex < form.fields.count - 1 {
                return form.fields[currentFieldIndex + 1].name
            }
            return nil
        }
        if fieldState.last == true {
            if visitHistory.count > 0 {
                let lastFieldName = visitHistory.last?.name
                return lastFieldName
            }
            return currentFieldName
        }
        if fieldState.end == true {
            return nil
        }
        if fieldState.moveToId != nil {
            return fieldState.moveToId
        }
        if fieldState.selectOption != nil {
            let moveTo = getPriorityMoveToEvent(moveToEvents: fieldState.selectOption?.behaviors ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldNames?.first
            }
        }
        if fieldState.validYes == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventValidYesAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldNames?.first
            }
        }
        if fieldState.validNo == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventValidNoAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldNames?.first
            }
        }
        if fieldState.valid == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventValidAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldNames?.first
            }
        }
        if fieldState.valid == false {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventInvalidAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldNames?.first
            }
        }
        let currentFieldIndex = form.fields.firstIndex(where: { $0.name == currentFieldName })
        if let currentFieldIndex = currentFieldIndex, currentFieldIndex < form.fields.count - 1 {
            return form.fields[currentFieldIndex + 1].name
        }
        return nil
    }

    // get the highest priority moveTo event from a list of eventsp
    private func getPriorityMoveToEvent(moveToEvents: [FieldBehavior]) -> FieldBehavior? {
        // events with true modifiers are highest priority
        if moveToEvents.count == 0 {
            return nil
        }
        let modifierEvents = moveToEvents.filter { $0.modifier != nil }
        for event in modifierEvents {
            if modifierIsTrue(modifier: event.modifier!) {
                return event
            }
        }
        return moveToEvents[0]
    }

    private func modifierIsTrue(modifier: FieldEventModifier) -> Bool {
        switch modifier {
        case .modifierFieldsUnresolved:
            return false
        }
    }

    private func genReplyMessageReceived(message: WebSocketServerMessage) {
        // chunk gen reply contents into sentences and pipe to output
        if message.type == SERVER_TO_CLIENT_MESSAGES.genReplyStart {
            return
        }
        if message.type == SERVER_TO_CLIENT_MESSAGES.genReplyEnd {
            emitEvent(.genReplyRequestEnd, nil)
            let field = form.fields.first(where: { $0.name == currentFieldName })
            fieldState[currentFieldName]?.valid = message.valid == true ? true : false
            fieldState[currentFieldName]?.skip = message.skip == true ? true : false
            fieldState[currentFieldName]?.last = message.last == true ? true : false
            fieldState[currentFieldName]?.end = message.end == true ? true : false
            fieldState[currentFieldName]?.moveToId = message.moveToId ?? nil
            fieldState[currentFieldName]?.validYes = message.validYes == true ? true : false
            fieldState[currentFieldName]?.validNo = message.validNo == true ? true : false

            if let numberString = message.number {
                fieldState[currentFieldName]?.number = Double(numberString)
            } else {
                fieldState[currentFieldName]?.number = nil
            }
            if let optionValue = message.selectOption {
                let selectedOption = field?.validation.selectOptions?.first(where: { $0.value == optionValue })
                if let selectedOption = selectedOption {
                    fieldState[currentFieldName]?.selectOption = selectedOption
                } else {
                    fieldState[currentFieldName]?.valid = false
                }
            }
            if let options = message.selectOptions {
                let optionArray = options.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let selectedOptions = field?.validation.selectOptions?.filter { option in
                    optionArray.contains(option.value)
                }
                if selectedOptions?.count ?? 0 > 0 {
                    fieldState[currentFieldName]?.selectOptions = selectedOptions
                } else {
                    fieldState[currentFieldName]?.valid = false
                }
            }
            addCurrentFieldToVisitHistory()
            addCurrentFieldToFieldHistory(input: nil, genReply: message.data)
            moveToNextField()
            return
        }
        VeConfig.vePrint("VECONVO: Outputting Gen sentence: \(message.data ?? "No data")")
        emitEvent(.audioOutMessage, message.data ?? "")
    }

    private func getFieldQuestion(fieldName: String) -> String {
        let fieldState = fieldState[fieldName]
        let field = form.fields.first(where: { $0.name == fieldName })
        if fieldState?.visitCount == 0 {
            let behaviorOutput = field?.eventConfig[.eventInitialQuestion]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field?.question ?? ""
        }
        if fieldState?.valid == true {
            let behaviorOutput = field?.eventConfig[.eventRevisitAfterResolved]?
                .filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return "\(outputsMoveToPrefix.randomElement() ?? "") \(field?.question ?? "")"
        }
        if fieldState?.valid == false {
            let behaviorOutput = field?.eventConfig[.eventRevisitAfterUnresolved]?
                .filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return "\(outputsMoveToPrefix.randomElement() ?? "") \(field?.question ?? "")"
        }
        return field?.question ?? ""
    }

    private func getFieldQuestionAppend(fieldName: String) -> String {
        let field = form.fields.first(where: { $0.name == fieldName })
        let selectOptionList = field?.validation.selectOptions?.filter { $0.readAloud == true }.map { $0.label } ?? []
        let selectOptionListAppend = selectOptionList
            .count > 0 ? " The options are: \(selectOptionList.joined(separator: ", "))." : ""
        return selectOptionListAppend
    }

    private func addCurrentFieldToFieldHistory(input: String?, genReply: String?) {
        let field = form.fields.first(where: {$0.name == currentFieldName})
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
            moveToId: fieldState[currentFieldName]!.moveToId
        ))
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
            fieldName = getNextFieldName(fieldName: currentField)
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
            fieldName = getNextFieldName(fieldName: currentField)
        }
        return completeEntries
    }

    private func buildFullConversationState() -> ConversationState {
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
}

private func getAnswerFromFieldState(fieldState: FieldState, field: Field) -> ConversationAnswerType {
    switch field.type {
    case .textarea:
        return .string(fieldState.textarea ?? "")
    case .number:
        return .double(fieldState.number ?? 0)
    case .yesNo:
        if fieldState.validYes == true {
            return .string("yes")
        } else if fieldState.validNo == true {
            return .string("no")
        } else {
            return .string("")
        }
    case .select:
        return .string(fieldState.selectOption?.value ?? "")
    case .multiselect:
        return .string(fieldState.selectOptions?.map { $0.value }.joined(separator: ", ") ?? "")
    default:
        return .string("getAnswerFromFieldState not implemented for type: \(field.type)")
    }
}
