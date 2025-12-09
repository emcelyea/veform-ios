import Foundation

struct FieldState {
    var fieldId: String
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
        fieldId: String,
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
        self.fieldId = fieldId
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
    private var currentFieldId: String
    private var initialFieldId: String
    private var fieldState: [String: FieldState] = [:]
    private var visitHistory: [FieldState] = []
    init(
        form: Form,
        emitEvent: @escaping (ConversationEvent, String?) -> Void,
        onComplete: @escaping (ConversationState) -> Void
    ) {
        self.form = form
        self.emitEvent = emitEvent
        self.onComplete = onComplete
        genReply = GenReply(form: form)
        initialFieldId = self.form.fields[0].id
        currentFieldId = self.form.fields[0].id
        for field in form.fields {
            fieldState[field.id] = FieldState(fieldId: field.id, valid: false, visitCount: 0)
        }
        Task {
            await genReply.start(onMessage: self.genReplyMessageReceived)
            emitEvent(.websocketSetup, nil)
        }
    }

    func start() {
        let initialQuestion: String = getFieldQuestion(fieldId: currentFieldId)
        let initialQuestionAppend: String = getFieldQuestionAppend(fieldId: currentFieldId)
        print("Initial question: \(initialQuestion + initialQuestionAppend)")
        emitEvent(.audioOutMessage, initialQuestion + initialQuestionAppend)
        logMessage(type: .initialQuestion, fieldId: currentFieldId, message: initialQuestion + initialQuestionAppend)
    }

    func stop() {
        genReply.tewyWebsockets?.closeConnection()
    }

    func inputReceived(input: String) {
        fieldState[currentFieldId]?.valid = false
        let field = form.fields.first(where: { $0.id == currentFieldId })
        guard let field = field else {
            print("Error, field \(currentFieldId) not found")
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
            print("Error, unknown field type \(field.id))")
        }
    }

    func setCurrentField(id: String) {
        fieldState[currentFieldId]?.moveToId = id
        moveToNextField()
    }

    func getCurrentField() -> Field? {
        return form.fields.first(where: { $0.id == currentFieldId })
    }

    func getFieldStateEntry(id: String) -> ConversationStateEntry? {
        let field = form.fields.first(where: { $0.id == id })
        guard let field = field else {
            return nil
        }
        let answer = getAnswerFromFieldState(fieldState: fieldState[id]!, field: field)
        return ConversationStateEntry(
            id: field.id,
            fieldName: field.name,
            question: field.prompts.question[0] ?? "",
            answer: answer,
            type: field.type,
            valid: fieldState[id]?.valid ?? false
        )
    }

    func getConversationState() -> ConversationState {
        return buildFullConversationState()
    }

    func setFieldState(id: String, state: ConversationStateEntry) {
        let field = form.fields.first(where: { $0.id == id })
        guard let field = field else {
            print("Error, field \(id) not found")
            return
        }
        fieldState[id] = FieldState(fieldId: id, valid: state.valid, visitCount: fieldState[id]?.visitCount ?? 0)

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
            fieldState[id]?.validYes = answerString == "yes" ? true : false
            fieldState[id]?.validNo = answerString == "no" ? true : false
        } else if field.type == .select {
            let selectOption = field.validation.selectOptions?.first(where: { $0.value == answerString })
            fieldState[id]?.selectOption = selectOption
        } else if field.type == .multiselect {
            let selected = answerString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let selectOptions = field.validation.selectOptions?.filter { selected.contains($0.value) }
            fieldState[id]?.selectOptions = selectOptions
        } else if field.type == .textarea {
            fieldState[id]?.textarea = answerString
        } else if field.type == .number {
            fieldState[id]?.number = answerDouble
        }
    }

    private func handleInputYesNoField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldId]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldId]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldId]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldId]?.moveToId = hotPhraseReply.moveToId ?? nil

        let yesNoReply = rulesValidation.validateYesNo()
        fieldState[currentFieldId]?.validYes = yesNoReply.answer == .yes ? true : false
        fieldState[currentFieldId]?.validNo = yesNoReply.answer == .no ? true : false
        fieldState[currentFieldId]?.valid = yesNoReply.valid

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldId]!)
        emitEvent(.audioOutMessage, nextOutput)
        // logMessage(type: .rulesMessage, fieldId: currentFieldId, message: nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputSelectField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldId]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldId]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldId]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldId]?.moveToId = hotPhraseReply.moveToId ?? nil

        let selectReply = rulesValidation.validateSelect()
        fieldState[currentFieldId]?.valid = selectReply.valid
        fieldState[currentFieldId]?.selectOption = selectReply.selectOption ?? nil

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldId]!)
        emitEvent(.audioOutMessage, nextOutput)
        // logMessage(type: .rulesMessage, fieldId: currentFieldId, message: nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputMultiselectField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldId]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldId]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldId]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldId]?.moveToId = hotPhraseReply.moveToId ?? nil

        let multiselectReply = rulesValidation.validateMultiselect()
        fieldState[currentFieldId]?.valid = multiselectReply.valid
        fieldState[currentFieldId]?.selectOptions = multiselectReply.selectOptions ?? nil

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldId]!)
        emitEvent(.audioOutMessage, nextOutput)
        // logMessage(type: .rulesMessage, fieldId: currentFieldId, message: nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputTextareaField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldId]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldId]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldId]?.end = hotPhraseReply.end ?? false
        fieldState[currentFieldId]?.textarea = input
        // we cant really validate a textarea with rules, so we just moveToNext to trigger llm
        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldId]!)
        emitEvent(.audioOutMessage, nextOutput)
        // logMessage(type: .rulesMessage, fieldId: currentFieldId, message: nextOutput)
        moveToNextField(input: input)
    }

    private func handleInputNumberField(input: String, field: Field) {
        let rulesValidation = RulesValidation(input: input, field: field)
        let hotPhraseReply = rulesValidation.validateHotPhrases()
        fieldState[currentFieldId]?.skip = hotPhraseReply.skip ?? false
        fieldState[currentFieldId]?.last = hotPhraseReply.last ?? false
        fieldState[currentFieldId]?.end = hotPhraseReply.end ?? false

        let numberReply = rulesValidation.validateNumber()
        fieldState[currentFieldId]?.valid = numberReply.valid
        fieldState[currentFieldId]?.number = numberReply.number

        let nextOutput = getResponseOutput(field: field, fieldState: fieldState[currentFieldId]!)
        emitEvent(.audioOutMessage, nextOutput)
        // logMessage(type: .rulesMessage, fieldId: currentFieldId, message: nextOutput)
        moveToNextField(input: input)
    }

    private func endForm() {
        print("Ending form")
        addCurrentFieldToHistory()
        // if we say moveTo
        print("Testing incomplete fields")
        if moveToAnyIncompleteField(root: initialFieldId) != nil {
            return
        }
        let completeEntries = buildCompletedConversation()
        onComplete(completeEntries)
    }

    private func moveToNextField(input: String? = nil, noVisit: Bool = false, traversing: Bool = false) {
        if fieldState[currentFieldId]?.valid == true || fieldState[currentFieldId]?
            .skip == true || fieldState[currentFieldId]?.last == true || fieldState[currentFieldId]?
            .end == true || fieldState[currentFieldId]?.moveToId != nil
        {
            guard let nextFieldId = getNextFieldId(fieldId: currentFieldId) else {
                endForm()
                return
            }

            if !noVisit {
                addCurrentFieldToHistory()
                fieldState[currentFieldId]?.visitCount += 1
            }
            let field = form.fields.first(where: { $0.id == nextFieldId })
            guard let field = field else {
                print("Error, tried to move to fieldId \(nextFieldId) but it doesn't exist")
                return
            }
            print("Moving to fieldId: \(nextFieldId) \(field.prompts.question.first ?? "No question")")
            fieldState[currentFieldId]?.skip = false
            fieldState[currentFieldId]?.last = false
            fieldState[currentFieldId]?.end = false
            fieldState[currentFieldId]?.moveToId = nil
            currentFieldId = nextFieldId
            if fieldState[nextFieldId]?.valid == true, traversing == true {
                return moveToNextField(noVisit: true, traversing: true)
            }
            emitEvent(.fieldChanged, currentFieldId)
            let nextQuestion = getFieldQuestion(fieldId: nextFieldId)
            let nextQuestionAppend: String = getFieldQuestionAppend(fieldId: nextFieldId)
            emitEvent(.audioOutMessage, nextQuestion + nextQuestionAppend)
            // if info immediately move on
            if field.type == .info {
                fieldState[nextFieldId]?.valid = true
                moveToNextField()
            }
            // fieldState is bad, ask llm
        } else {
            if let input = input {
                emitEvent(.genReplyRequestStart, nil)
                genReply.sendMessage(fieldId: currentFieldId, type: .genReplyRequest, input: input)
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
            return field.prompts.acknowledgeSkip.randomElement() ?? ""
        }

        if fieldState.last == true {
            if visitHistory.count == 0 {
                return "There is no last question to revisit, gonna repeat this one: \(field.prompts.question.randomElement() ?? "")"
            }

            let behaviorOutput = field.eventConfig[.eventLastRequested]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field.prompts.acknowledgeLast.randomElement() ?? ""
        }

        if fieldState.end == true {
            let behaviorOutput = field.eventConfig[.eventEndRequested]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field.prompts.acknowledgeEnd.randomElement() ?? ""
        }

        if fieldState.moveToId != nil {
            // TODO: moveto logic and events
            return field.prompts.acknowledgeSkip.randomElement() ?? ""
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
                return field.prompts.acknowledgeEnd.randomElement() ?? ""
            }
            return field.prompts.acknowledgeSuccess.randomElement() ?? ""
        }
        if fieldState.valid == false {
            let behaviorOutput = field.eventConfig[.eventInvalidAnswer]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field.prompts.thinking.randomElement() ?? ""
        }
        return field.prompts.acknowledgeSuccess.randomElement() ?? ""
    }

    private func getNextFieldId(fieldId: String) -> String? {
        let fieldState = fieldState[fieldId]
        let field = form.fields.first(where: { $0.id == fieldId })
        guard let field = field, let fieldState = fieldState else {
            print("Error, field \(fieldId) not found")
            return nil
        }
        if fieldState.skip == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventSkipRequested] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldIds?.first
            }
            let currentFieldIndex = form.fields.firstIndex(where: { $0.id == currentFieldId })
            if let currentFieldIndex = currentFieldIndex, currentFieldIndex < form.fields.count - 1 {
                return form.fields[currentFieldIndex + 1].id
            }
            return nil
        }
        if fieldState.last == true {
            print("last requested, visitHistory: \(visitHistory.count) \(visitHistory.last)")
            if visitHistory.count > 0 {
                let lastFieldId = visitHistory.last?.fieldId
                print("last fieldId: \(lastFieldId)")
                return lastFieldId
            }
            return currentFieldId
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
                return moveTo.moveToFieldIds?.first
            }
        }
        if fieldState.validYes == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventValidYesAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldIds?.first
            }
        }
        if fieldState.validNo == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventValidNoAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldIds?.first
            }
        }
        if fieldState.valid == true {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventValidAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldIds?.first
            }
        }
        if fieldState.valid == false {
            let moveTo = getPriorityMoveToEvent(moveToEvents: field.eventConfig[.eventInvalidAnswer] ?? [])
            if let moveTo = moveTo {
                return moveTo.moveToFieldIds?.first
            }
        }
        // no moveTo found, get nextFieldId in order if exists
        let currentFieldIndex = form.fields.firstIndex(where: { $0.id == currentFieldId })
        if let currentFieldIndex = currentFieldIndex, currentFieldIndex < form.fields.count - 1 {
            return form.fields[currentFieldIndex + 1].id
        }
        return nil
    }

    // get the highest priority moveTo event from a list of eventsp
    private func getPriorityMoveToEvent(moveToEvents: [FieldBehavior]) -> FieldBehavior? {
        // events with true modifiers are highest priority
        if moveToEvents.count == 0 {
            return nil
        }
        var priorityEvent = moveToEvents[0]
        let modifierEvents = moveToEvents.filter { $0.modifier != nil }
        for event in modifierEvents {
            if modifierIsTrue(modifier: event.modifier!) {
                return event
            }
        }
        return priorityEvent
    }

    // OK DEBUG AND THEN START TESTING OND EVICE DANG
    private func modifierIsTrue(modifier: FieldEventModifier) -> Bool {
        switch modifier {
        case .modifierFieldsUnresolved:
            return false
        }
        return false
    }

    private func genReplyMessageReceived(message: WSUnpackedMessage) {
        // chunk gen reply contents into sentences and pipe to output
        if message.type == .genReplyStart {
            return
        }
        if message.type == .genReplyEnd {
            emitEvent(.genReplyRequestEnd, nil)
            let field = form.fields.first(where: { $0.id == currentFieldId })
            fieldState[currentFieldId]?.valid = message.otherData?["valid"] == "true" ? true : false
            fieldState[currentFieldId]?.skip = message.otherData?["skip"] == "true" ? true : false
            fieldState[currentFieldId]?.last = message.otherData?["last"] == "true" ? true : false
            fieldState[currentFieldId]?.end = message.otherData?["end"] == "true" ? true : false
            fieldState[currentFieldId]?.moveToId = message.otherData?["moveToId"] ?? nil
            fieldState[currentFieldId]?.validYes = message.otherData?["validyes"] == "true" ? true : false
            fieldState[currentFieldId]?.validNo = message.otherData?["validno"] == "true" ? true : false
         
                     print("gen reply message received \(message.otherData)")
    print("fieldstate after gen reply \(fieldState[currentFieldId])")
   if let numberString = message.otherData?["number"] {
                fieldState[currentFieldId]?.number = Double(numberString)
            } else {
                fieldState[currentFieldId]?.number = nil
            }
            if let optionValue = message.otherData?["option"] {
                let selectedOption = field?.validation.selectOptions?.first(where: { $0.value == optionValue })
                if let selectedOption = selectedOption {
                    fieldState[currentFieldId]?.selectOption = selectedOption
                } else {
                    fieldState[currentFieldId]?.valid = false
                }
            }
            if let options = message.otherData?["options"] {
                let optionArray = options.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let selectedOptions = field?.validation.selectOptions?.filter { option in
                    optionArray.contains(option.value)
                }
                if selectedOptions?.count ?? 0 > 0 {
                    fieldState[currentFieldId]?.selectOptions = selectedOptions
                } else {
                    fieldState[currentFieldId]?.valid = false
                }
            }

            moveToNextField()
            return
        }
        print("Outputting Gen sentence: \(message.body)")
        emitEvent(.audioOutMessage, message.body)
    }

    private func logMessage(type: CLIENT_TO_SERVER_MESSAGES, fieldId: String, message: String) {
        genReply.sendMessage(fieldId: fieldId, type: type, input: message)
    }

    private func getFieldQuestion(fieldId: String) -> String {
        let fieldState = fieldState[fieldId]
        let field = form.fields.first(where: { $0.id == fieldId })
        if fieldState?.visitCount == 0 {
            let behaviorOutput = field?.eventConfig[.eventInitialQuestion]?.filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field?.prompts.question.randomElement() ?? ""
        }
        if fieldState?.valid == true {
            let behaviorOutput = field?.eventConfig[.eventRevisitAfterResolved]?
                .filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field?.prompts.questionMoveTo.randomElement() ?? ""
        }
        if fieldState?.valid == false {
            let behaviorOutput = field?.eventConfig[.eventRevisitAfterUnresolved]?
                .filter { $0.type == .behaviorOutput } ?? []
            if behaviorOutput.count > 0 {
                return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
            }
            return field?.prompts.questionMoveTo.randomElement() ?? ""
        }
        return field?.prompts.question.randomElement() ?? ""
    }

    private func getFieldQuestionAppend(fieldId: String) -> String {
        let fieldState = fieldState[fieldId]
        let field = form.fields.first(where: { $0.id == fieldId })
        let selectOptionList = field?.validation.selectOptions?.filter { $0.readAloud == true }.map { $0.label } ?? []
        let selectOptionListAppend = selectOptionList
            .count > 0 ? " The options are: \(selectOptionList.joined(separator: ", "))." : ""
        return selectOptionListAppend
    }

    // this gets run at the end of a field processing, so should contain
    // state of input response and what not
    private func addCurrentFieldToHistory() {
        visitHistory.append(FieldState(
            fieldId: fieldState[currentFieldId]!.fieldId,
            valid: fieldState[currentFieldId]!.valid,
            visitCount: fieldState[currentFieldId]!.visitCount,
            validYes: fieldState[currentFieldId]!.validYes,
            validNo: fieldState[currentFieldId]!.validNo,
            selectOption: fieldState[currentFieldId]!.selectOption
        ))
    }

    private func moveToAnyIncompleteField(root: String?) -> Bool? {
        var fieldId = root
        var previousFieldId = root
        while fieldId != nil {
            guard let id = fieldId else {
                return nil
            }
            print("Testing fieldId: \(fieldId) valid: \(fieldState[id]?.valid)")
            if fieldState[id]?.valid == false {
                currentFieldId = previousFieldId ?? currentFieldId
                emitEvent(.audioOutMessage, "Looks like we have a required question we need to revisit")
                moveToNextField(noVisit: true, traversing: true)
                return true
            }
            previousFieldId = id
            fieldId = getNextFieldId(fieldId: fieldId ?? "")
        }
        return nil
    }

    private func buildCompletedConversation() -> ConversationState {
        // start at initialField
        var fieldId: String? = initialFieldId
        var completeEntries: [ConversationStateEntry] = []
        while let id = fieldId {
            let field = form.fields.first(where: { $0.id == id })
            if field?.type != .info {
                let answer = getAnswerFromFieldState(fieldState: fieldState[id]!, field: field!)
                completeEntries.append(ConversationStateEntry(
                    id: id,
                    fieldName: field?.name ?? "",
                    question: field?.prompts.question[0] ?? "",
                    answer: answer,
                    type: field?.type ?? .textarea,
                    valid: true
                ))
            }
            fieldId = getNextFieldId(fieldId: id)
        }
        return completeEntries
    }

    private func buildFullConversationState() -> ConversationState {
        var conversationState: ConversationState = []
        for field in form.fields {
            let answer = getAnswerFromFieldState(fieldState: fieldState[field.id]!, field: field)
            conversationState.append(ConversationStateEntry(
                id: field.id,
                fieldName: field.name,
                question: field.prompts.question[0] ?? "",
                answer: answer,
                type: field.type,
                valid: fieldState[field.id]!.valid
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
