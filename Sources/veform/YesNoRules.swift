//
//  yesNoReply.swift
//  conversation-app
//
//  Created by Eric McElyea on 10/27/25.
//

import Foundation

enum YesNoAnswer: String {
    case yes
    case no
}

struct YesNoReply {
    let valid: Bool
    let answer: YesNoAnswer?
    init(valid: Bool, answer: YesNoAnswer?) {
        self.valid = valid
        self.answer = answer
    }
}
func getYesNoReply(sentiment: Double?, lemmas: [String], field _: Field, threshold: Double = 0.6) -> YesNoReply {
    let sentimentWeight = 0.3
    var noScore = 0.0
    var yesScore = 0.0
    let strongYesMatches = fuzzyMatch(lemmas: lemmas, expected: strongYes)
    let weakYesMatches = fuzzyMatch(lemmas: lemmas, expected: weakYes)
    let strongNoMatches = fuzzyMatch(lemmas: lemmas, expected: strongNo)
    let weakNoMatches = fuzzyMatch(lemmas: lemmas, expected: weakNo)

    let totalMatches = strongYesMatches + weakYesMatches + strongNoMatches + weakNoMatches
    let sentimentScore = abs(sentiment ?? 0) * sentimentWeight
    if sentiment ?? 0 < 0 {
        noScore = Double(strongNoMatches + weakNoMatches) / Double(totalMatches) + sentimentScore
        yesScore = Double(strongYesMatches + weakYesMatches) / Double(totalMatches) - sentimentScore
    } else {
        noScore = Double(strongNoMatches + weakNoMatches) / Double(totalMatches) - sentimentScore
        yesScore = Double(strongYesMatches + weakYesMatches) / Double(totalMatches) + sentimentScore
    }
    if noScore > yesScore {
        if noScore > threshold {
            return YesNoReply(valid: true, answer: .no)
        }
    } else {
        if yesScore > threshold {
            return YesNoReply(valid: true, answer: .yes)
        }
    }
    return YesNoReply(valid: false, answer: nil)
}

// Strong affirmative responses
let strongYes = [
    "yes",
    "yeah",
    "yep",
    "yup",
    "absolutely",
    "definitely",
    "certainly",
    "of course",
    "sure",
    "indeed",
    "correct",
    "affirmative",
    "agreed",
    "exactly",
    "precisely",
    "without a doubt",
    "for sure",
    "no doubt",
    "100%",
    "totally",
    "completely",
]

// Weak affirmative responses
let weakYes = [
    "maybe",
    "perhaps",
    "possibly",
    "probably",
    "i think so",
    "i guess",
    "i suppose",
    "sort of",
    "kind of",
    "i guess so",
    "likely",
    "most likely",
    "i believe so",
    "somewhat",
    "more or less",
    "okay",
    "ok",
    "fine",
    "alright",
]

// Strong negative responses
let strongNo = [
    " no ",
    " nope ",
    " nah ",
    "absolutely not ",
    "definitely not ",
    "certainly not ",
    "of course not ",
    "never",
    "no way",
    " not at all",
    "negative",
    "incorrect",
    " not a chance",
    " no chance",
    "by no means",
    " not in the slightest",
    "under no circumstances",
    "out of the question",
    "impossible",
    "not possible",
]

// Weak negative responses
let weakNo = [
    "probably not",
    "i don't think so",
    "unlikely",
    "i doubt it",
    "doubtful",
    "not really",
    "not exactly",
    "i'm not sure",
    "unsure",
    "not likely",
    "doesn't seem like it",
    "i wouldn't say so",
    "not particularly",
    "hardly",
    "barely",
]
