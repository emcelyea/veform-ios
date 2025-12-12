//
//  FormBuilder.swift
//
//
//  Created by Eric McElyea on 12/11/25.
//

import Foundation

public class FormBuilder {
    public var form: Form
    public init() {
        let uuid = UUID().uuidString
        form = Form(id: uuid, fields: [])
    }

    @discardableResult
    public func addField(
        question: String,
        name: String,
        type: FieldTypes,
        configure: ((inout Field) -> Void)? = nil
    ) -> Self {
        let root = form.fields.count == 0
        if form.fields.contains(where: { $0.name == name }) {
            print("Field with name \(name) already exists")
        }
        if !root {
            let lastFieldIndex = form.fields.count - 1
            if form.fields[lastFieldIndex].eventConfig[.eventValidAnswer]?.contains(where: { $0.type == .behaviorMoveTo }) == false {
                var lastField = form.fields[lastFieldIndex]
                lastField.addBehavior(event: .eventValidAnswer, behavior: FieldBehavior(type: .behaviorMoveTo, moveToFieldNames: [name]))
                form.fields[lastFieldIndex] = lastField
            }
        }
        var field = Field(name: name, type: type, root: root, question: question)
        configure?(&field)
        form.fields.append(field)
        return self
    }

    public func getField(name: String) -> Field? {
        return form.fields.first(where: { $0.name == name })
    }
}
