//
//  Chapter.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import Foundation

struct Chapter: Codable, Identifiable {
    let id: UUID
    let title: String
    let startTime: Double // in seconds
    let duration: Double // in seconds

    var endTime: Double {
        return startTime + duration
    }

    init(title: String, startTime: Double, duration: Double) {
        self.id = UUID()
        self.title = title
        self.startTime = startTime
        self.duration = duration
    }
}
