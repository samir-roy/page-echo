//
//  FileManager+Extensions.swift
//  audibooks
//
//  Created by Samir Roy on 11/2/25.
//

import Foundation

extension FileManager {
    /// Cached documents directory URL for the app
    /// This avoids repeated system queries for the documents directory path
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
