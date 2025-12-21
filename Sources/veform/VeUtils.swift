//
//  File.swift
//  
//
//  Created by Eric McElyea on 12/20/25.
//

import Foundation

func getNextFieldFromFieldState(currentFieldState: FieldState, form: Form, visitHistory: [FieldState]) -> Field? {
    let field = form.fields.first(where: { $0.name == currentFieldState.name })
    guard let field = field else {
        VeConfig.vePrint("VECONVO: Error, field \(currentFieldState.name) not found")
        return nil
    }
    if currentFieldState.skip == true {
        let moveTo = getEventBehavior(behaviors: field.eventConfig[.eventSkipRequested] ?? [], behavior: .behaviorMoveTo)
        if moveTo?.moveToFieldName != nil {
            return form.fields.first(where: { $0.name == moveTo?.moveToFieldName })
        }
        let currentFieldIndex = form.fields.firstIndex(where: { $0.name == currentFieldState.name })
        if let currentFieldIndex = currentFieldIndex, currentFieldIndex < form.fields.count - 1 {
            return form.fields[currentFieldIndex + 1]
        }
        return nil
    }
    if currentFieldState.end == true {
        return nil
    }
    if currentFieldState.last == true {
        if visitHistory.count > 0 {
            if visitHistory.last?.name != nil {
                let lastField = form.fields.first(where: { $0.name == visitHistory.last?.name })
                if lastField != nil {
                    return lastField
                }
            }
        }
    }
    if currentFieldState.moveToName != nil {
        return form.fields.first(where: { $0.name == currentFieldState.moveToName })
    }
    if currentFieldState.selectOption != nil {
        let moveTo = getEventBehavior(behaviors: currentFieldState.selectOption?.behaviors ?? [], behavior: .behaviorMoveTo)
        if moveTo?.moveToFieldName != nil {
            return form.fields.first(where: { $0.name == moveTo?.moveToFieldName })
        }
    }
    if currentFieldState.validYes == true {
        let moveTo = getEventBehavior(behaviors: field.eventConfig[.eventValidYesAnswer] ?? [], behavior: .behaviorMoveTo)
        if moveTo?.moveToFieldName != nil {
            return form.fields.first(where: { $0.name == moveTo?.moveToFieldName })
        }
    }
    if currentFieldState.validNo == true {
        let moveTo = getEventBehavior(behaviors: field.eventConfig[.eventValidNoAnswer] ?? [], behavior: .behaviorMoveTo)
        if moveTo?.moveToFieldName != nil {
            return form.fields.first(where: { $0.name == moveTo?.moveToFieldName })
        }
    }
    if currentFieldState.valid == true {
        let moveTo = getEventBehavior(behaviors: field.eventConfig[.eventValidAnswer] ?? [], behavior: .behaviorMoveTo)
        if moveTo?.moveToFieldName != nil {
            return form.fields.first(where: { $0.name == moveTo?.moveToFieldName })
        }
    }
    if currentFieldState.valid == false {
        let moveTo = getEventBehavior(behaviors: field.eventConfig[.eventInvalidAnswer] ?? [], behavior: .behaviorMoveTo)
        if moveTo?.moveToFieldName != nil {
            return form.fields.first(where: { $0.name == moveTo?.moveToFieldName })
        }
    }
    let currentFieldIndex = form.fields.firstIndex(where: { $0.name == field.name })
    if let currentFieldIndex = currentFieldIndex, currentFieldIndex < form.fields.count - 1 {
        return form.fields[currentFieldIndex + 1]
    }
    return nil
}

func getEventBehavior(behaviors: [FieldBehavior], behavior: BehaviorType) -> FieldBehavior? {
    return behaviors.first(where: { $0.type == behavior }) ?? nil
}

func getAnswerFromFieldState(fieldState: FieldState, field: Field) -> ConversationAnswerType {
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

func fieldStateFromConversationState(field: Field, state: ConversationStateEntry) -> FieldState {
    var fieldState = FieldState(name: field.name, valid: state.valid, visitCount: 0)

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
        fieldState.validYes = answerString == "yes" ? true : false
        fieldState.validNo = answerString == "no" ? true : false
    } else if field.type == .select {
        let selectOption = field.validation.selectOptions?.first(where: { $0.value == answerString })
        fieldState.selectOption = selectOption
    } else if field.type == .multiselect {
        let selected = answerString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let selectOptions = field.validation.selectOptions?.filter { selected.contains($0.value) }
        fieldState.selectOptions = selectOptions
    } else if field.type == .textarea {
        fieldState.textarea = answerString
    } else if field.type == .number {
        fieldState.number = answerDouble
    }
    return fieldState
}

func getResponseOutput(field: Field, fieldState: FieldState) -> String {
    if fieldState.skip == true {
        let behaviorOutput = field.eventConfig[.eventSkipRequested]?.filter { $0.type == .behaviorOutput } ?? []
        if behaviorOutput.count > 0 {
            return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
        }
        return outputsAcknowledgeSkip.randomElement() ?? ""
    }

    if fieldState.last == true {
        return outputsAcknowledgeLast.randomElement() ?? ""
    }

    if fieldState.end == true {
        let behaviorOutput = field.eventConfig[.eventEndRequested]?.filter { $0.type == .behaviorOutput } ?? []
        if behaviorOutput.count > 0 {
            return behaviorOutput.map { $0.output ?? "" }.joined(separator: "\n")
        }
        return outputsAcknowledgeEnd.randomElement() ?? ""
    }

    if fieldState.moveToName != nil {
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



func updateStateFromMessage(message: WebSocketServerMessage, field: Field, fieldState: FieldState) -> FieldState {
    var updatedFieldState = fieldState
    if message.type == SERVER_TO_CLIENT_MESSAGES.genReplyStart {
        updatedFieldState.genReplyRunning = true
    }
    if message.type == SERVER_TO_CLIENT_MESSAGES.hotPhraseSkip {
        updatedFieldState.hotPhraseSkipResolved = true
        if message.skip == true {
            updatedFieldState.skip = true
        }
    }
    if message.type == SERVER_TO_CLIENT_MESSAGES.hotPhraseLast {
        updatedFieldState.hotPhraseLastResolved = true
        if message.last == true {
            updatedFieldState.last = true
        }
    }
    if message.type == SERVER_TO_CLIENT_MESSAGES.hotPhraseEnd {
        updatedFieldState.hotPhraseEndResolved = true
        if message.end == true {
            updatedFieldState.end = true
        }
    }
    if message.type == SERVER_TO_CLIENT_MESSAGES.hotPhraseMoveTo {
        updatedFieldState.hotPhraseMoveToResolved = true
        if message.moveToName != nil {
            updatedFieldState.moveToName = message.moveToName
        }
    }
    if message.type == SERVER_TO_CLIENT_MESSAGES.genReplyEnd {
        updatedFieldState.valid = message.valid == true ? true : false
        updatedFieldState.validYes = message.validYes == true ? true : false
        updatedFieldState.validNo = message.validNo == true ? true : false

        if let numberString = message.number {
            updatedFieldState.number = Double(numberString)
        } else {
            updatedFieldState.number = nil
        }
        if let optionValue = message.selectOption {
            let selectedOption = field.validation.selectOptions?.first(where: { $0.value == optionValue })
            if let selectedOption = selectedOption {
                updatedFieldState.selectOption = selectedOption
            } else {
                updatedFieldState.valid = false
            }
        }
        if let options = message.selectOptions {
            let optionArray = options.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let selectedOptions = field.validation.selectOptions?.filter { option in
                optionArray.contains(option.value)
            }
            if selectedOptions?.count ?? 0 > 0 {
                updatedFieldState.selectOptions = selectedOptions
            } else {
                updatedFieldState.valid = false
            }
        }
        updatedFieldState.genReplyRunning = false
        return updatedFieldState
    }
    return updatedFieldState
}
