//
//  TewyTypes.swift
//  conversation-app
//
//  Created by Eric McElyea on 9/30/25.
//

import Foundation

// #########################################################
// FORM TYPES AND VALIDATORS THESE SHOULD MATCH types IN TYPES.TS
// #########################################################
public enum ConversationAnswerType {
    case string(String)
    case double(Double)

      public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    
    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }
}
public enum ConversationEvent: String {
    case audioInChunk
    case audioInMessage
    case audioOutChunk
    case audioOutMessage
    case listening
    case speaking
    case fieldChanged
    case genReplyRequestStart
    case genReplyRequestEnd
    case websocketSetup
    case audioSetup
    case error
}

public struct ConversationEvenData {
    public let fieldId: String
    public let text: String?
    public let number: Double?
    public init(fieldId: String, text: String?, number: Double?) {
        self.fieldId = fieldId
        self.text = text
        self.number = number
    }
}
public struct ConversationStateEntry {
    public let id: String
    public let fieldName: String
    public let question: String
    public let answer: ConversationAnswerType
    public let type: FieldTypes
    public let valid: Bool

    public init(id: String, fieldName: String, question: String, answer: ConversationAnswerType, type: FieldTypes, valid: Bool) {
        self.id = id
        self.fieldName = fieldName
        self.question = question
        self.answer = answer
        self.type = type
        self.valid = valid
    }
}

public typealias ConversationState = [ConversationStateEntry]

public enum FieldTypes: String, Codable {
    case textarea
    case select
    case multiselect
    case yesNo
    case number
    case date
    case info
}

struct Field: Codable {
    let name: String
    let type: FieldTypes
    let prompts: FieldPrompts
    let validation: FieldValidation
    let eventConfig: FieldEventConfig
    let id: String
    init(
        name: String,
        type: FieldTypes,
        prompts: FieldPrompts,
        validation: FieldValidation,
        eventConfig: FieldEventConfig,
        id: String
    ) {
        self.name = name
        self.type = type
        self.prompts = prompts
        self.validation = validation
        self.eventConfig = eventConfig
        self.id = id
    }
}

struct FieldPrompts: Codable {
    let question: [String]
    let questionMoveTo: [String]
    let thinking: [String]
    let acknowledgeSuccess: [String]
    let acknowledgeSkip: [String]
    let acknowledgeLast: [String]
    let acknowledgeEnd: [String]
    init(
        question: [String],
        questionMoveTo: [String],
        thinking: [String],
        acknowledgeSuccess: [String],
        acknowledgeSkip: [String],
        acknowledgeLast: [String],
        denySkip: [String],
        acknowledgeEnd: [String]
    ) {
        self.question = question // plays when question is asked
        self.questionMoveTo = questionMoveTo // plays when question is moved back to after start
        self.thinking = thinking // plays when genReply is initiated
        self.acknowledgeSuccess = acknowledgeSuccess // plays when users answer is valid
        self.acknowledgeSkip = acknowledgeSkip // plays when user desire to skip is accepted
        self.acknowledgeLast = acknowledgeLast // plays when user desire to revisit the last question is accepted
        self.acknowledgeEnd = acknowledgeEnd // plays when user desire to end the conversation is accepted
    }
}


struct FieldValidation: Codable {
    let required: Bool?
    let selectOptions: [SelectOption]?
    let selectSubject: String?
    let maxCharacters: Int?
    let minCharacters: Int?
    let minValue: Double?
    let maxValue: Double?
    let maxSelections: Int?
    let minSelections: Int?
    let minDate: Date?
    let maxDate: Date?
    let minDateRange: Date?
    let maxDateRange: Date?
    init(
        required: Bool? = true,
        selectOptions: [SelectOption]? = nil,
        selectSubject: String? = nil,
        maxCharacters: Int? = nil,
        minCharacters: Int? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        maxSelections: Int? = nil,
        minSelections: Int? = nil,
        minDate: Date? = nil,
        maxDate: Date? = nil,
        minDateRange: Date? = nil,
        maxDateRange: Date? = nil
    ) {
        self.selectOptions = selectOptions
        self.selectSubject = selectSubject
        self.required = required
        self.maxCharacters = maxCharacters
        self.minCharacters = minCharacters
        self.minValue = minValue
        self.maxValue = maxValue
        self.maxSelections = maxSelections
        self.minSelections = minSelections
        self.minDate = minDate
        self.maxDate = maxDate
        self.minDateRange = minDateRange
        self.maxDateRange = maxDateRange
    }
}

struct SelectOption: Codable {
    let label: String
    let value: String
    let behaviors: [FieldBehavior]?
    let readAloud: Bool?
    init(label: String, value: String, behaviors: [FieldBehavior]? = nil, readAloud: Bool? = false) {
        self.label = label
        self.value = value
        self.behaviors = behaviors
        self.readAloud = readAloud
    }
}

enum FieldEvent: String, Codable {
    case eventInitialQuestion
    case eventValidAnswer
    case eventInvalidAnswer
    case eventValidYesAnswer
    case eventValidNoAnswer
    case eventSkipRequested
    case eventLastRequested
    case eventEndRequested
    case eventRevisitAfterResolved
    case eventRevisitAfterUnresolved
}

enum FieldEventModifier: String, Codable {
    case modifierFieldsUnresolved
}

enum BehaviorType: String, Codable {
    case behaviorMoveToLast // jump back to question before this one, use to build more complex flows
    case behaviorOutput // output a string
    case behaviorMoveToFirstUnresolved // move to first unresolved field in list
    case behaviorMoveTo // move to field
    case behaviorEnd // end entire convo
}

struct FieldBehavior: Codable {
    let type: BehaviorType
    let moveToFieldIds: [String]?
    let resolvesField: Bool?
    let output: String?
    let modifier: FieldEventModifier?
    init(type: BehaviorType, moveToFieldIds: [String]? = nil, resolvesField: Bool? = true, output: String? = nil, modifier: FieldEventModifier? = nil) {
        self.type = type
        self.moveToFieldIds = moveToFieldIds
        self.resolvesField = resolvesField
        self.output = output
        self.modifier = modifier
    }
}

struct FieldEventConfig: Codable {
    var events: [FieldEvent: [FieldBehavior]]
    
    init(events: [FieldEvent: [FieldBehavior]] = [:]) {
        self.events = events
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dictionary = try container.decode([String: [FieldBehavior]].self)
        
        var events: [FieldEvent: [FieldBehavior]] = [:]
        for (key, value) in dictionary {
            if let fieldEvent = FieldEvent(rawValue: key) {
                events[fieldEvent] = value
            }
        }
        self.events = events
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var dictionary: [String: [FieldBehavior]] = [:]
        for (key, value) in events {
            dictionary[key.rawValue] = value
        }
        try container.encode(dictionary)
    }
    
    subscript(key: FieldEvent) -> [FieldBehavior]? {
        get { events[key] }
        set { events[key] = newValue }
    }
}

struct Form: Codable {
    let id: String
    let fields: [Field]
    init(id: String, fields: [Field]) {
        self.id = id
        self.fields = fields
    }
}

func validateFields(_ fields: [Field]) -> Bool {
    let requiredPrompts = [
        "question",
        "thinking",
        "more_info",
        "acknowledge_success",
        "acknowledge_skip",
        "acknowledge_end",
    ]
    for field in fields {
        let fieldName = field.name ?? ""
        let fieldType = field.type
        if fieldName.isEmpty {
            print("Invalid rules, field name is empty")
            return false
        }
        let fieldPrompts = field.prompts
        if fieldPrompts.question.isEmpty {
            print("Invalid rules, question prompt is missing for field: \(fieldName)")
            return false
        }
        if fieldPrompts.thinking.isEmpty {
            print("Invalid rules, thinking prompt is missing for field: \(fieldName)")
            return false
        }
        if fieldPrompts.questionMoveTo.isEmpty {
            print("Invalid rules, more_info prompt is missing for field: \(fieldName)")
            return false
        }
        if fieldPrompts.acknowledgeSuccess.isEmpty {
            print("Invalid rules, acknowledge_success prompt is missing for field: \(fieldName)")
            return false
        }
        if fieldPrompts.acknowledgeSkip.isEmpty {
            print("Invalid rules, acknowledge_skip prompt is missing for field: \(fieldName)")
            return false
        }
        if fieldPrompts.acknowledgeEnd.isEmpty {
            print("Invalid rules, acknowledge_end prompt is missing for field: \(fieldName)")
            return false
        }
    }
    return true
}
