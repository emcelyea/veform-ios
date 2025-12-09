//
//  skipQuestion.swift
//  conversation-app
//
//  Created by Eric McElyea on 10/29/25.
//

import Foundation


func testSkipRequested(lemmas: [String], input: String) -> Bool {
    if input.count > 50  {
        return false
    }
    let hitPercentage = getLemmasHitPercentage(lemmas: lemmas, input: input, strongWordList: hardSkipWords, weakWordList: softSkipWords)
    return hitPercentage > 0.5
}

let hardSkipWords: [String] = [
    "skip this",
    "skip it",
    "skip question",
    "move on",
    "go next",
    "go on",
    "go to the next",
    "go to next",
    "different question",
    "another question",
    "won't answer",
    "pass on this",
    "ignore this",
    "ignore question",
    "ignore this question",
    "ignore this one",
    "ignore this one question",
    "ignore this one question",
    "next question",
    "next one",
    "another question",
    "come back to th",
    "come back later",
    "let's move on",
    "shall we move on",
    "onto the next",
    "following question",
    "following one",
    "can't answer",
    "no answer",
    "no comment",
    "i am done"
]
let softSkipWords: [String] = [
    "pass",
    "next",
    "skip",
    "ignore",
    "continue",
    "not now",
    "later",
    "forward",
    "move on",
    "move forward",
    "more",
    "i don't want",
    "i won't",
    "i can't",
    "go to"
]
