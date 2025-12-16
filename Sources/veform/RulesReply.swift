//
//  ConversationRules.swift
//  conversation-app
//
//  Created by Eric McElyea on 9/29/25.
//

import Foundation
import NaturalLanguage

// import Ifrit

struct HotPhraseReply {
    var skip: Bool?
    var last: Bool?
    var moveToId: String?
    var end: Bool?
    init(skip: Bool? = nil, last: Bool? = nil, moveToId: String? = nil, end: Bool? = nil) {
        self.skip = skip
        self.last = last
        self.moveToId = moveToId
        self.end = end
    }
}
// ips: 192.168.11.198 - states
class RulesValidation {
    var input: String
    var field: Field
    var sentiment: Double?
    var lemmas: [String]
    init(input: String, field: Field) {
        self.input = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.field = field
        let (sentiment, lemmas) = extractSentimentAndLemmas(text: input)
        self.sentiment = sentiment
        self.lemmas = lemmas
    }

    // validates if user wants to skip, go to last, exit entirely, or move to speicfic field
    func validateHotPhrases() -> HotPhraseReply {
        if testSkipRequested(lemmas: lemmas, input: input) {
            return HotPhraseReply(skip: true)
        }
        if testLastRequested(lemmas: lemmas, input: input) {
            return HotPhraseReply(last: true)
        }
        let moveToId = testMoveToRequested(input: input)
        if moveToId != nil {
            return HotPhraseReply(moveToId: moveToId!)
        }
        if testEndRequested(lemmas: lemmas, input: input) {
            return HotPhraseReply(end: true)
        }
        return HotPhraseReply()
    }

    func validateYesNo() -> YesNoReply {
        return getYesNoReply(sentiment: sentiment, lemmas: lemmas, field: field)
    }

    func validateSelect() -> SelectReply {
        return getSelectReply(input: input, field: field)
    }

    func validateMultiselect() -> MultiselectReply {
        return getMultiselectReply(input: input, field: field)
    }

    func validateNumber() -> NumberReply {
        return getNumberReply(input: input, lemmas: lemmas, field: field)
    }
}


func testMoveToRequested(input: String) -> String? {
    let moveToId = input.lowercased().contains("move to") ? input.lowercased().split(separator: "move to").last?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    return moveToId
}

func fuzzyMatch(lemmas: [String], expected: [String]) -> Int {
    var matchCount = 0
    for lemma in lemmas {
        if expected.contains(lemma) {
            matchCount += 1
        }
    }
    // let fuse = Fuse(threshold: 0.02)
    // for lemma in lemmas {
    //     let results = fuse.searchSync(lemma, in: expected)
    //     if results.count > 0 {
    //         matchCount += 1
    //     }
    // }
    return matchCount
}

func extractSentimentAndLemmas(text: String) -> (Double?, [String]) {
    let tagger = NLTagger(tagSchemes: [.sentimentScore, .lemma])
    tagger.string = text

    let (sentimentTag, _) = tagger.tag(
        at: text.startIndex,
        unit: .paragraph,
        scheme: .sentimentScore
    )

    var sentiment = 0.0
    if let score = sentimentTag?.rawValue, let value = Double(score) {
        sentiment = value
    }

    // Extract lemmas word by word
    var lemmas: [String] = []

    tagger.enumerateTags(in: text.startIndex ..< text.endIndex,
                            unit: .word,
                            scheme: .lemma)
    { tag, tokenRange in
        if let lemma = tag?.rawValue {
            lemmas.append(lemma.lowercased())
        } else {
            // If no lemma found, use the original word
            let word = String(text[tokenRange]).lowercased()
            if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lemmas.append(word)
            }
        }
        return true
    }

    return (sentiment, lemmas)
}

func getLemmasHitPercentage(lemmas: [String], input: String, strongWordList: [String], weakWordList: [String]) -> Double {
    var hardMatches = ""
    strongWordList.forEach { word in
        if input.contains(word) {
            hardMatches += word
        }
    }
    var softMatches = 0
    weakWordList.forEach { word in
        if  lemmas.contains(word) {
            softMatches += 1
        }
    }
    let softHitPercentage = Double(softMatches) / Double(lemmas.count)
    let hardHitPercentage = Double(hardMatches.count) / Double(input.count) * 1.5
    let totalHitPercentage = (softHitPercentage + hardHitPercentage)
    return totalHitPercentage
}

struct SelectReply: Codable {
    let valid: Bool
    let selectOption: SelectOption?
    init(valid: Bool, selectOption: SelectOption? = nil) {
        self.valid = valid
        self.selectOption = selectOption
    }
}
// TODO fuzzy variant of matching here, and a confirmation if we have low probability of match
func getSelectReply(input: String, field: Field) -> SelectReply {
    var selectedOptions:[SelectOption] = []
    let selectOptions = field.validation.selectOptions ?? []
    for option in selectOptions {
        if input.lowercased().contains(option.label.lowercased()) {
            selectedOptions.append(option)
        }
    }
    if selectedOptions.count == 1 {
        return SelectReply(valid: true, selectOption: selectedOptions[0])
    }
    return SelectReply(valid: false)
}


struct NumberReply {
    var valid: Bool
    var number: Double?
    init(valid: Bool, number: Double? = nil) {
        self.number = number
        self.valid = valid
    }
}

func getNumberReply(input: String, lemmas: [String], field: Field) -> NumberReply {
    let numberRegex = #"\b(\d+\.?\d*)\b"#
    let wordRegex = "\\b(none|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|trillion)\\b"
    
    if input.count > 50  {
        return NumberReply(valid: false)
    }
    // check lemmas for number
    for lemma in lemmas {
       if let match = lemma.range(of: numberRegex, options: .regularExpression) {
            let extractedString = String(lemma[match])
            if let number = stringToNumber(extractedString) {
                if (field.validation.minValue == nil || number >= field.validation.minValue!) &&
                   (field.validation.maxValue == nil || number <= field.validation.maxValue!) {
                    return NumberReply(valid: true, number: number)

                }
            }
        }
        if let match = lemma.range(of: wordRegex, options: .regularExpression) {
            let extractedString = String(lemma[match])
            if let number = wordToNumber(extractedString) {
                if (field.validation.minValue == nil || number >= field.validation.minValue!) &&
                   (field.validation.maxValue == nil || number <= field.validation.maxValue!) {
                    return NumberReply(valid: true, number: number)
                }
            }
        }
    }
    let match = input.range(of: numberRegex, options: .regularExpression) ?? input.range(of: wordRegex, options: .regularExpression)
    if let match = match {
        let extractedString = String(input[match])
        if let number = stringToNumber(extractedString) {
            if (field.validation.minValue == nil || number >= field.validation.minValue!) &&
               (field.validation.maxValue == nil || number <= field.validation.maxValue!) {
                return NumberReply(valid: true, number: number)
            }
        }
    }
    return NumberReply(valid:false)
}


func wordToNumber(_ word: String) -> Double? {
    let lowercased = word.lowercased()
    
    let numberMap: [String: Double] = [
        "none": 0,
        "zero": 0,
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10,
        "eleven": 11,
        "twelve": 12,
        "thirteen": 13,
        "fourteen": 14,
        "fifteen": 15,
        "sixteen": 16,
        "seventeen": 17,
        "eighteen": 18,
        "nineteen": 19,
        "twenty": 20,
        "thirty": 30,
        "forty": 40,
        "fifty": 50,
        "sixty": 60,
        "seventy": 70,
        "eighty": 80,
        "ninety": 90,
        "hundred": 100,
        "thousand": 1000,
        "million": 1000000,
        "billion": 1000000000,
        "trillion": 1000000000000
    ]
    
    return numberMap[lowercased]
}

func stringToNumber(_ text: String) -> Double? {
    if let number = Double(text) {
        return number
    }
    
    return wordToNumber(text)
}


struct MultiselectReply: Codable {
    let valid: Bool
    let selectOptions: [SelectOption]?
    init(valid: Bool, selectOptions: [SelectOption]? = nil) {
        self.valid = valid
        self.selectOptions = selectOptions
    }
}

func getMultiselectReply(input: String, field: Field) -> MultiselectReply {
    var selectedOptions:[SelectOption] = []
    let multiselectOptions = field.validation.selectOptions ?? []
    for option in multiselectOptions {
        if input.lowercased().contains(option.label.lowercased()) {
            selectedOptions.append(option)
        }
    }
    if selectedOptions.count > 0 {
        if let maxSelections = field.validation.maxSelections {
            if selectedOptions.count > maxSelections {
                return MultiselectReply(valid: false, selectOptions: nil)
            }
        }
        if let minSelections = field.validation.minSelections {
            if selectedOptions.count < minSelections {
                return MultiselectReply(valid: false, selectOptions: nil)
            }
        }
        return MultiselectReply(valid: true, selectOptions: selectedOptions)
    }
    return MultiselectReply(valid: false, selectOptions: nil)
}


func testEndRequested(lemmas: [String], input: String) -> Bool {
    if input.count > 50  {
        return false
    }
    let hitPercentage = getLemmasHitPercentage(lemmas: lemmas, input: input, strongWordList: hardEndWords, weakWordList: softEndWords)
    return hitPercentage > 0.6
}


let hardEndWords: [String] = [
    "end form",
    "end conversation",
    "stop conversation",
    "close conversation",
    "terminate conversation",
    "cancel conversation",
    "abort conversation",
    "end chat",
    "stop chat",
    "close chat",
    "exit chat",
    "quit chat",
    "cancel chat",
    "abort chat",
    "leave chat",
    "end session",
    "close session",
    "terminate session",
    "end this",
    "stop this",
    "i'm done",
    "im done",
    "i am done",
    "we're done",
    "were done",
    "we are done",
    "that's all",
    "thats all",
    "that is all",
    "no more questions",
    "cancel",
    "abort",
    "goodbye",
    "good bye",
    "bye bye",
]

let softEndWords: [String] = [
    "quit",
    "exit",
    "cancel",

]
