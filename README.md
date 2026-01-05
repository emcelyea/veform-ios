# Veform

This is the ios library for running veform in ios.

Veform is a simple library for turning traditional input sets into audio conversations.

The idea behind veform is that inputting data into a device shouldn't be a painful, tedious process for users. A conversational audio input should be an option, and all inputs should offer the level of accessibility that an audio conversation provides.

## What is it

Veform is a set of libraries for different platforms (iOS, Android, Web) and a server that drives the conversation.

Veform does not store anything, it is a middle layer between the user and your code. It manages audio input, output, and converts abstract audio inputs into discrete values for your code. It handles special inputs like: "go back to the first question", "actually for the question about dogs I wanted to say xxx", "can you tell me more about y?". It is a highly flexible and customizable tool for adding conversational audio into your app without compromising your design at all.

## Installation

Add this package to your project using Swift Package Manager:

dependencies: [
    .package(url: "https://github.com/YOUR_USERNAME/veform-ios.git", from: "1.0.0")
]## Usage

## Basic form setup
import veform

let veform = Veform()
form = Veform()
let formBuilder = FormBuilder()
formBuilder.addField(question: "Welcome!", name: "welcome", type: .info)

formBuilder.addField(question: "How are you doing today?", name: "howAreYou", type: .select) { field in
    field.addSelectOption(label: "Bad", value: "bad")
    field.addSelectOption(label: "Ok", value: "ok")
    field.addSelectOption(label: "Good", value: "good")
}

formBuilder.addField(question: "What did you do at work today?", name: "workDay", type: .textarea)

formBuilder.addField(question: "How did you feel today from 1 to 10?", name: "howFeel"){ field in
    field.validation.minValue = 1
    field.validation.maxValue = 10
}

formBuilder.addField(question: "Are you all done?", name: "question", type: .yesNo) { field in
    field.addBehavior(event: .eventValidYesAnswer, behavior: FieldBehavior(type: .behaviorMoveTo, moveToFieldName: "howAreYou"))
    field.addBehavior(event: .eventValidNoAnswer, behavior: FieldBehavior(type: .behaviorMoveTo, moveToFieldName: "goodbyeMessage"))
}

formBuilder.addField(question: "Great have a nice day!", name: "goodbyeMessage", type: .info)
form?.start(form: formBuilder.form)

## Customization

Veform is designed around a graph of nodes that represent the conversation. We provide a `FormBuilder` class to help create the conversation graph that represents your Form.

You can build a form and pass it to veform and it will guide users through the conversation based on the rules you provide.

You can also completely customize behavior by intercepting events. Veform events all follow the "Cancelable Event Pattern". 

You can hook into these events to perform UI/UX updates, or override default behaviors.

Examples:

// display user audio in as it comes in
form.onAudioInChunk { data in
    myViewVariables.userAudio += data
}

// Override the default field movement defined in FormBuilder
form.onFieldChanged { previous, next in
   if previous.name == "rateOurService", customRateValidator(previous) {
    form.setCurrentField("goodbye")
    return true
   } else {
    form.setCurrentField("rateOurService")
    return true
   }
}
