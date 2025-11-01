//
//  UserDefaults+Extensions.swift
//  audibooks
//
//  Created by Samir Roy on 11/2/25.
//

import Foundation

extension UserDefaults {
    /// Keys used for storing user preferences
    private enum Keys {
        static let lastPlayedAudiobookID = "lastPlayedAudiobookID"
    }

    /// The ID of the last played audiobook as a string
    var lastPlayedAudiobookID: String? {
        get { string(forKey: Keys.lastPlayedAudiobookID) }
        set { set(newValue, forKey: Keys.lastPlayedAudiobookID) }
    }
}
