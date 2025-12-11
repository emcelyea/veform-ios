//
//  FormBuilder.swift
//
//
//  Created by Eric McElyea on 12/11/25.
//

import Foundation

public class FormBuilder {
    public var form: Form
    init() {
        let uuid = UUID().uuidString
        form = Form(id: uuid, fields: [])
    }

    // ok so we gotta be able to add a field but reference other fields as well
    func addField(question: String, name: String, type: FieldTypes) -> Field? {
        let root = form.fields.count == 0
        if form.fields.contains(where: { $0.name == name }) {
            print("Field with name \(name) already exists")
            return nil
        }
        let field = Field(name: name, type: type, root: root, question: question)
        form.fields.append(field)
        if !root {
            if form.fields[form.fields.count - 1].eventConfig?[.eventValidAnswer]?.contains(where: { $0.type == .behaviorMoveTo }) == false {
                form.fields[form.fields.count - 1].addBehavior(event:.eventValidAnswer, behavior: FieldBehavior(type: .behaviorMoveTo, moveToFieldIds: [name]))
            }
        }
        return field
    }

    func getField(name: String) -> Field? {
        return form.fields.first(where: { $0.name == name })
    }
}
