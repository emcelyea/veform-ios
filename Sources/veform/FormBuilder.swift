//
//  FormBuilder.swift
//
//
//  Created by Eric McElyea on 12/11/25.
//

import Foundation

public enum Voice: String, Codable {
    case female1 = "female-1"
    case female2 = "female-2"
    case male1 = "male-1"
    case male2 = "male-2"
}

public enum VoiceLanguage: String, Codable {
    case enUS = "en-US"
    case enGB = "en-GB"
    case enAU = "en-AU"
}

public struct VoiceOptions: Codable {
    public var voice: Voice
    public var language: VoiceLanguage

    public init(voice: Voice, language: VoiceLanguage) {
        self.voice = voice
        self.language = language
    }
}

public struct VeformConfig: Codable {
    public var voice: VoiceOptions?
    public var localTime: String?
    public var description: String?

    public init(voice: VoiceOptions? = nil, localTime: String? = nil, description: String? = nil) {
        self.voice = voice
        self.localTime = localTime
        self.description = description
    }
}

public class FormBuilder {
    public var form: Form
    private var fields: [Field] = []
    public private(set) var config: VeformConfig

    public init(config: VeformConfig? = nil) {
        let uuid = UUID().uuidString
        form = Form(id: uuid, fields: [])
        if let config {
            self.config = config
            self.config.localTime = localTime24()
            return
        }
        self.config = VeformConfig(localTime: localTime24(), description: "")
    }

    @discardableResult
    public func addField(
        question: String,
        name: String,
        type: FieldTypes,
        configure: ((inout Field) -> Void)? = nil
    ) -> Field? {
        if getField(name: name) != nil {
            log("Field with name \(name) already exists", type: .error)
            return nil
        }
        if name.isEmpty || question.isEmpty {
            log("Field with name \(name) and question \(question) has invalid name or question", type: .error)
            return nil
        }

        var field = Field(name: name, type: type, root: fields.isEmpty, question: question)
        configure?(&field)
        fields.append(field)
        syncFormFields()
        return field
    }

    public func getField(name: String) -> Field? {
        return fields.first(where: { $0.name == name })
    }

    public func getFields() -> [Field] {
        return fields
    }

    @discardableResult
    public func removeField(name: String) -> Bool {
        guard let index = fields.firstIndex(where: { $0.name == name }) else {
            return false
        }
        fields.remove(at: index)
        syncFormFields()
        return true
    }

    private func syncFormFields() {
        form = Form(id: form.id, fields: fields)
    }

    private enum LogType {
        case error
        case warn
        case debug
    }

    private func log(_ message: String, type: LogType) {
        if type == .debug {
            return
        }
        print("Veform Builder: \(message)")
    }
}

private func localTime24() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: Date())
}
