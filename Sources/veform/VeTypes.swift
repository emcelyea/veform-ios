//
//  TewyTypes.swift
//  conversation-app
//
//  Created by Eric McElyea on 9/30/25.
//

import Foundation

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
    case loadingStarted
    case loadingFinished
    case runningStarted
    case runningFinished
    case audioInStart
    case audioInChunk
    case audioInEnd
    case audioOutStart
    case audioOutEnd
    case listening
    case speaking
    case fieldChanged
    case error
}


public struct ConversationStateEntry {
    public let name: String
    public let question: String
    public let answer: ConversationAnswerType
    public let type: FieldTypes
    public let valid: Bool

    public init(name: String, question: String, answer: ConversationAnswerType, type: FieldTypes, valid: Bool) {
        self.name = name
        self.question = question
        self.answer = answer
        self.type = type
        self.valid = valid
    }
}

public typealias ConversationState = [ConversationStateEntry]

struct GenReplyRequest: Codable {
    let fieldName: String
    let fieldHistory: [FieldHistory]
}

struct HotPhraseRequest: Codable {
    let fieldName: String
    let question: String
    let input: String
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
    var moveToName: String?
    var hotPhraseSkipResolved: Bool?
    var hotPhraseLastResolved: Bool?
    var hotPhraseEndResolved: Bool?
    var hotPhraseMoveToResolved: Bool?
    var genReplyRunning: Bool?
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
        moveToName: String? = nil
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
        self.moveToName = moveToName
    }
}

public enum FieldTypes: String, Codable {
    case textarea
    case select
    case multiselect
    case yesNo
    case number
    case date
    case info
}

public struct Field: Codable {
    let name: String
    let type: FieldTypes
    let root: Bool
    // let validation: FieldValidation
    // let eventConfig: FieldEventConfig
    let question: String
    var eventConfig: FieldEventConfig
    public var validation: FieldValidation
    mutating public func addBehavior(event: FieldEvent, behavior: FieldBehavior) {
        if self.eventConfig[event] == nil {
            self.eventConfig[event] = [behavior]
        } else {
            self.eventConfig[event]?.append(behavior)
        }
    }
    
    @discardableResult
    mutating public func addSelectOption(label: String, value: String, readAloud: Bool = false) {
        if self.validation.selectOptions == nil {
            self.validation.selectOptions = [SelectOption(label: label, value: value, readAloud: readAloud)]
        } else {
            self.validation.selectOptions?.append(SelectOption(label: label, value: value, readAloud: readAloud))
        }
    }

    @discardableResult
    mutating public func addSelectSubject(subject: String){
        self.validation.selectSubject = subject
    }

    @discardableResult
    mutating public func addSelectOptionBehavior(value: String, behavior: FieldBehavior) {
        let optionIndex = self.validation.selectOptions?.firstIndex(where: { $0.value == value })
        if let optionIndex = optionIndex {
            self.validation.selectOptions?[optionIndex].addBehavior(behavior: behavior)
        } else {
            VeConfig.vePrint("VESELECTOPTION: Select option with value \(value) not found")
        }
    }

    mutating public func addValidation(validation: FieldValidation) {
        self.validation = validation
    }

    init(
        name: String,
        type: FieldTypes,
        root: Bool,
        question: String
    ) {
        self.name = name
        self.type = type
        self.root = root
        self.question = question
        self.eventConfig = FieldEventConfig()
        self.validation = FieldValidation()
    }
}

public struct FieldValidation: Codable {
    public var validate: Bool?
    var selectOptions: [SelectOption]?
    var selectSubject: String?
    public var maxCharacters: Int?
    public var minCharacters: Int?
    public var minValue: Double?
    public var maxValue: Double?
    public var maxSelections: Int?
    public var minSelections: Int?
    init(
        validate: Bool? = true,
        selectOptions: [SelectOption]? = nil,
        selectSubject: String? = nil,
        maxCharacters: Int? = nil,
        minCharacters: Int? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        maxSelections: Int? = nil,
        minSelections: Int? = nil
    ) { 
        self.validate = validate
        self.selectOptions = selectOptions
        self.selectSubject = selectSubject
        self.maxCharacters = maxCharacters
        self.minCharacters = minCharacters
        self.minValue = minValue
        self.maxValue = maxValue
        self.maxSelections = maxSelections
        self.minSelections = minSelections
    }
}

struct SelectOption: Codable {
    let label: String
    let value: String
    var behaviors: [FieldBehavior]?
    let readAloud: Bool?
 
    mutating func addBehavior(behavior: FieldBehavior) {
        if self.behaviors == nil {
            self.behaviors = [behavior]
        } else {
            self.behaviors?.append(behavior)
        }
    }
    init(label: String, value: String, behaviors: [FieldBehavior]? = nil, readAloud: Bool? = false) {
        self.label = label
        self.value = value
        self.behaviors = behaviors
        self.readAloud = readAloud
    }
}

public enum FieldEvent: String, Codable {
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

public enum BehaviorType: String, Codable {
    case behaviorMoveToLast // jump back to question before this one, use to build more complex flows
    case behaviorOutput // output a string
    case behaviorMoveToFirstUnresolved // move to first unresolved field in list
    case behaviorMoveTo // move to field
    case behaviorEnd // end entire convo
}

public struct FieldBehavior: Codable {
    public let type: BehaviorType
    public let moveToFieldName: String?
    public let resolvesField: Bool?
    public let output: String?
    public init(type: BehaviorType, moveToFieldName: String? = nil, resolvesField: Bool? = true, output: String? = nil) {
        self.type = type
        self.moveToFieldName = moveToFieldName
        self.resolvesField = resolvesField
        self.output = output
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

public struct Form: Codable {
    let id: String
    var fields: [Field]
    init(id: String, fields: [Field]) {
        self.id = id
        self.fields = fields
    }
}

public enum VeformError: Error {
    case fieldAlreadyExists(name: String)
}
