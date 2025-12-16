//
//  File.swift
//  
//
//  Created by Eric McElyea on 12/9/25.
//

import Foundation

func testLastRequested(lemmas: [String], input: String) -> Bool {
    if input.count > 50  {
        return false
    }
    let hitPercentage = getLemmasHitPercentage(lemmas: lemmas, input: input, strongWordList: hardLastWords, weakWordList: softLastWords)
    return hitPercentage > 0.5
}
let hardLastWords: [String] = [
    "go back",
    "to previous",
    "previous question",
    "last question",
    "go to the previous",
    "go to the last one",
    "back to previous",
    "back to last",
    "return to previous",
    "return to last",
    "go to prior",
    "prior question",
    "the previous one",
    "the last one",
    "show previous",
    "show last",
    "take me back",
    "go backwards",
    "move back",
    "step back",
    "previous one",
    "last one",
    "go to the one before",
    "the one before",
    "back one",
    "one back",
    "earlier question",
    "go to earlier",
    "show me the previous",
    "show me the last one"
]

let softLastWords: [String] =  [
    "back",
    "previous",
    "last",
    "prior",
    "before",
    "earlier",
    "go back",
    "move back",
    "step back",
    "backwards",
    "backward",
    "last one",
    "previous one",
    "go previous"
]
