//
//  TimeInterval+Extensions.swift
//  audibooks
//
//  Created by Samir Roy on 11/2/25.
//

import Foundation

extension TimeInterval {
    /// Formats the time interval as a string in the format "h:mm:ss" or "m:ss"
    /// - Returns: Formatted time string
    func formattedTime() -> String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
