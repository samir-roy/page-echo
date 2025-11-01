//
//  Audiobook.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import Foundation
import SwiftData

@Model
final class Audiobook {
    var id: UUID
    var title: String
    var coverImageURL: String?
    @Attribute(.externalStorage) var coverImageData: Data?
    var audioURL: String // Original URL (for reference)
    var localFilePath: String? // Path to downloaded file in app's Documents directory
    var currentPosition: Double // Current playback position in seconds
    var duration: Double // Total duration in seconds
    var chaptersData: Data? // Encoded chapters
    var _playbackSpeed: Float? // Internal storage for playback speed
    var lastPlayedDate: Date? // Last time this book was played

    private var _cachedChapters: [Chapter]? // Cached chapters to avoid repeated JSON decoding

    var playbackSpeed: Float {
        get { _playbackSpeed ?? 1.0 }
        set { _playbackSpeed = newValue }
    }

    var percentComplete: Double {
        guard duration > 0 else { return 0 }
        return (currentPosition / duration) * 100
    }

    var chapters: [Chapter] {
        get {
            if let cached = _cachedChapters {
                return cached
            }

            guard let data = chaptersData else {
                _cachedChapters = []
                return []
            }

            let decoded = (try? JSONDecoder().decode([Chapter].self, from: data)) ?? []
            _cachedChapters = decoded
            return decoded
        }
        set {
            chaptersData = try? JSONEncoder().encode(newValue)
            _cachedChapters = newValue
        }
    }

    init(title: String, coverImageURL: String? = nil, coverImageData: Data? = nil, audioURL: String, localFilePath: String? = nil, currentPosition: Double = 0, duration: Double = 0, chapters: [Chapter] = [], playbackSpeed: Float = 1.0) {
        self.id = UUID()
        self.title = title
        self.coverImageURL = coverImageURL
        self.coverImageData = coverImageData
        self.audioURL = audioURL
        self.localFilePath = localFilePath
        self.currentPosition = currentPosition
        self.duration = duration
        self._playbackSpeed = playbackSpeed
        self.chaptersData = try? JSONEncoder().encode(chapters)
    }
}
