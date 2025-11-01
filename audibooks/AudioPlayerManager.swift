//
//  AudioPlayerManager.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import SwiftData
import MediaPlayer

@MainActor
class AudioPlayerManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var currentAudiobook: Audiobook?
    @Published var currentChapter: Chapter?
    @Published var sleepTimerRemaining: TimeInterval? = nil
    @Published var playbackError: String? = nil

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var saveTimer: Timer?
    private var sleepTimer: Timer?
    private var sleepTimerEndTime: Date?
    private var sleepTimerType: SleepTimerType = .minutes(0)
    private var modelContext: ModelContext?
    private var nextChapterBoundaryTime: Double?
    private var isUIUpdatesPaused = false

    enum SleepTimerType {
        case minutes(Int)
        case endOfChapters(Int)
    }

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandHandlers()
        setupInterruptionHandling()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    private func updateNowPlayingInfo() {
        guard let audiobook = currentAudiobook else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()

        // Title and metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = audiobook.title
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.audioBook.rawValue

        // Chapter info if available
        if let chapter = currentChapter {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = chapter.title
        }

        // Playback info
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0

        // Cover art
        if let coverData = audiobook.coverImageData,
           let image = UIImage(data: coverData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func setupRemoteCommandHandlers() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.isPlaying {
                    self.togglePlayPause()
                }
            }
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isPlaying {
                    self.togglePlayPause()
                }
            }
            return .success
        }

        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.togglePlayPause()
            }
            return .success
        }

        // Skip forward command (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.skipForward(30)
            }
            return .success
        }

        // Skip backward command (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.skipBackward(15)
            }
            return .success
        }

        // Next track command (for next chapter)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.nextChapter()
            }
            return .success
        }

        // Previous track command (for previous chapter)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.previousChapter()
            }
            return .success
        }

        // Change playback position command
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.seek(to: event.positionTime)
            }
            return .success
        }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                if isPlaying {
                    isPlaying = false
                    stopTimer()
                    updateNowPlayingInfo()
                }

            case .ended:
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return
                }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

                if options.contains(.shouldResume) {
                    audioPlayer?.play()
                    isPlaying = true
                    startTimer()
                    updateNowPlayingInfo()
                }

            @unknown default:
                break
            }
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func pauseUIUpdates() {
        isUIUpdatesPaused = true
        stopTimer()
    }

    func resumeUIUpdates() {
        isUIUpdatesPaused = false

        // Sync UI state with actual player state
        if let player = audioPlayer {
            currentTime = player.currentTime
            currentAudiobook?.currentPosition = player.currentTime
            updateCurrentChapter()
        }

        updateSleepTimerRemaining()

        if isPlaying {
            startTimer()
        }
    }

    func loadAudiobook(_ audiobook: Audiobook) {
        if currentAudiobook?.id == audiobook.id {
            return
        }

        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            stopTimer()
        }

        currentAudiobook = audiobook
        playbackError = nil

        guard let filename = audiobook.localFilePath else {
            playbackError = "Audio file not found. The audiobook may need to be re-downloaded."
            print("No local file path for audiobook")
            return
        }

        // Construct full path from filename
        let documentsPath = FileManager.documentsDirectory
        let url = documentsPath.appendingPathComponent(filename)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            playbackError = "Audio file not found at: \(filename)"
            print("Audio file does not exist at path: \(url.path)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.enableRate = true
            playbackSpeed = audiobook.playbackSpeed
            audioPlayer?.rate = playbackSpeed
            duration = audioPlayer?.duration ?? 0
            currentTime = audiobook.currentPosition
            audioPlayer?.currentTime = currentTime

            if audiobook.duration == 0 {
                audiobook.duration = duration
            }

            audiobook.lastPlayedDate = Date()
            UserDefaults.standard.lastPlayedAudiobookID = audiobook.id.uuidString

            updateCurrentChapter()
            updateNowPlayingInfo()
            startSaveTimer()
        } catch {
            playbackError = "Could not load audiobook: \(error.localizedDescription)"
            print("Error loading audio from local file: \(error)")
        }
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
            savePosition()
        } else {
            player.play()
            isPlaying = true
            startTimer()
            savePosition()
        }

        updateNowPlayingInfo()
    }

    func seek(to time: Double) {
        audioPlayer?.currentTime = time
        // The actual player time may differ slightly due to audio frame boundaries
        let actualTime = audioPlayer?.currentTime ?? time
        updateCurrentChapter(for: actualTime)
        currentTime = actualTime
        currentAudiobook?.currentPosition = actualTime
        savePosition()
        updateNowPlayingInfo()
    }

    func skipForward(_ seconds: Double = 15) {
        guard let player = audioPlayer else { return }
        let newTime = min(player.currentTime + seconds, duration)
        seek(to: newTime)
    }

    func skipBackward(_ seconds: Double = 15) {
        guard let player = audioPlayer else { return }
        let newTime = max(player.currentTime - seconds, 0)
        seek(to: newTime)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioPlayer?.rate = speed
        currentAudiobook?.playbackSpeed = speed
        updateNowPlayingInfo()
    }

    func nextChapter() {
        guard let audiobook = currentAudiobook, !audiobook.chapters.isEmpty else { return }

        // Find current chapter index
        if let currentChapterIndex = audiobook.chapters.firstIndex(where: { $0.id == currentChapter?.id }) {
            // Go to next chapter if available
            if currentChapterIndex + 1 < audiobook.chapters.count {
                let nextChapter = audiobook.chapters[currentChapterIndex + 1]
                seek(to: nextChapter.startTime)
            }
        } else if let firstChapter = audiobook.chapters.first {
            // If no current chapter, go to first chapter
            seek(to: firstChapter.startTime)
        }
    }

    func previousChapter() {
        guard let audiobook = currentAudiobook, !audiobook.chapters.isEmpty else { return }

        // If we're more than 3 seconds into the current chapter, restart it
        if let currentChap = currentChapter, currentTime - currentChap.startTime > 3 {
            seek(to: currentChap.startTime)
            return
        }

        // Find current chapter index
        if let currentChapterIndex = audiobook.chapters.firstIndex(where: { $0.id == currentChapter?.id }) {
            // Go to previous chapter if available
            if currentChapterIndex > 0 {
                let prevChapter = audiobook.chapters[currentChapterIndex - 1]
                seek(to: prevChapter.startTime)
            }
        }
    }

    func seekToChapter(_ chapter: Chapter) {
        seek(to: chapter.startTime)
    }

    func setSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil

        if minutes == 0 {
            sleepTimerEndTime = nil
            sleepTimerRemaining = nil
            sleepTimerType = .minutes(0)
        } else {
            sleepTimerType = .minutes(minutes)
            let interval = TimeInterval(minutes * 60)
            sleepTimerEndTime = Date().addingTimeInterval(interval)
            sleepTimerRemaining = interval

            sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleSleepTimerExpired()
                }
            }
        }
    }

    func setSleepTimerEndOfChapters(count: Int) {
        guard let audiobook = currentAudiobook,
              let chapter = currentChapter,
              !audiobook.chapters.isEmpty else { return }

        sleepTimer?.invalidate()
        sleepTimer = nil

        sleepTimerType = .endOfChapters(count)

        // Find the end time of the target chapter
        var targetEndTime = chapter.endTime

        if count > 1 {
            // Find current chapter index
            if let currentIndex = audiobook.chapters.firstIndex(where: { $0.id == chapter.id }) {
                // Calculate which chapter we should end at
                let targetIndex = min(currentIndex + count - 1, audiobook.chapters.count - 1)
                targetEndTime = audiobook.chapters[targetIndex].endTime
            }
        }

        let audioTimeRemaining = targetEndTime - currentTime
        let realTimeRemaining = audioTimeRemaining / Double(playbackSpeed)
        sleepTimerRemaining = max(0, realTimeRemaining)
        sleepTimerEndTime = Date().addingTimeInterval(realTimeRemaining)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: realTimeRemaining, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleSleepTimerExpired()
            }
        }
    }

    private func handleSleepTimerExpired() {
        sleepTimerEndTime = nil
        sleepTimerRemaining = nil
        sleepTimerType = .endOfChapters(0)
        sleepTimer = nil

        if isPlaying {
            togglePlayPause()
        }
    }

    private func updateSleepTimerRemaining() {
        guard let endTime = sleepTimerEndTime else {
            sleepTimerRemaining = nil
            return
        }

        let remaining = endTime.timeIntervalSinceNow
        sleepTimerRemaining = max(0, remaining)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                self.currentAudiobook?.currentPosition = player.currentTime

                // Update chapter when we cross a chapter boundary
                if let boundary = self.nextChapterBoundaryTime, player.currentTime >= boundary {
                    let previousChapter = self.currentChapter
                    self.updateCurrentChapter()

                    if previousChapter?.id != self.currentChapter?.id {
                        self.updateNowPlayingInfo()
                    }
                }

                self.updateSleepTimerRemaining()
            }
        }
    }

    private func updateCurrentChapter(for time: Double? = nil) {
        guard let audiobook = currentAudiobook else {
            currentChapter = nil
            nextChapterBoundaryTime = nil
            return
        }

        // Find the chapter that contains the time
        let timeToCheck = time ?? currentTime
        let chapter = audiobook.chapters.first { chapter in
            timeToCheck >= chapter.startTime && timeToCheck < chapter.endTime
        }

        if currentChapter?.id != chapter?.id {
            currentChapter = chapter
        }

        // Calculate when the next chapter starts
        calculateNextChapterBoundary(for: timeToCheck)
    }

    private func calculateNextChapterBoundary(for time: Double) {
        guard let audiobook = currentAudiobook, !audiobook.chapters.isEmpty else {
            nextChapterBoundaryTime = nil
            return
        }

        // Find the next chapter that starts after the current time
        nextChapterBoundaryTime = audiobook.chapters.first { chapter in
            chapter.startTime > time
        }?.startTime
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startSaveTimer() {
        saveTimer?.invalidate()

        // Save position every minute
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.savePosition()
            }
        }
    }

    private func savePosition() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            print("Error saving position: \(error)")
        }
    }

    nonisolated deinit {
        let currentTimer = timer
        let currentSaveTimer = saveTimer
        let currentSleepTimer = sleepTimer
        currentTimer?.invalidate()
        currentSaveTimer?.invalidate()
        currentSleepTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            stopTimer()
        }
    }
}
