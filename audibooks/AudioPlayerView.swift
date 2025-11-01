//
//  AudioPlayerView.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import SwiftUI

struct CustomProgressBar: View {
    let value: Double
    let range: ClosedRange<Double>
    let onSeek: (Double) -> Void
    let isDisabled: Bool

    @State private var isDragging = false
    @State private var dragValue: Double?

    private var displayValue: Double {
        dragValue ?? value
    }

    private var progress: CGFloat {
        let rangeSize = range.upperBound - range.lowerBound
        guard rangeSize > 0 else { return 0 }
        return CGFloat((displayValue - range.lowerBound) / rangeSize)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: isDragging ? 8 : 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: isDragging ? 16 : 8)

                // Progress fill
                RoundedRectangle(cornerRadius: isDragging ? 8 : 4)
                    .fill(Color.primary)
                    .frame(
                        width: max(0, geometry.size.width * progress),
                        height: isDragging ? 16 : 8
                    )
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDisabled {
                            // Set dragging state immediately on touch
                            if !isDragging {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    isDragging = true
                                }
                            }

                            // Only update drag value if moved at least 5 points
                            let dragDistance = sqrt(
                                pow(gesture.translation.width, 2) +
                                pow(gesture.translation.height, 2)
                            )

                            if dragDistance >= 5 {
                                // Calculate new value based on drag position
                                let percent = max(0, min(1, gesture.location.x / geometry.size.width))
                                let rangeSize = range.upperBound - range.lowerBound
                                let newValue = range.lowerBound + (Double(percent) * rangeSize)
                                dragValue = newValue
                            }
                        }
                    }
                    .onEnded { gesture in
                        if !isDisabled {
                            // Calculate drag distance
                            let dragDistance = sqrt(
                                pow(gesture.translation.width, 2) +
                                pow(gesture.translation.height, 2)
                            )

                            // Only seek if user actually dragged (not just tapped)
                            if dragDistance >= 5 {
                                let percent = max(0, min(1, gesture.location.x / geometry.size.width))
                                let rangeSize = range.upperBound - range.lowerBound
                                let newValue = range.lowerBound + (Double(percent) * rangeSize)

                                // Update playback position
                                onSeek(newValue)
                            }

                            // Reset drag state
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                isDragging = false
                                dragValue = nil
                            }
                        }
                    }
            )
        }
        .frame(height: 20) // Touch target height
    }
}

struct AudioPlayerView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    @State private var showChaptersList = false
    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    var onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.vertical, 8)
                .onTapGesture {
                    onCollapse()
                }

            Spacer()

            if let audiobook = playerManager.currentAudiobook {
                // Album art
                Group {
                    if let coverData = audiobook.coverImageData,
                       let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(16)
                            .clipped()
                    } else if let coverURL = audiobook.coverImageURL,
                              let url = URL(string: coverURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                        } placeholder: {
                            placeholderCover
                        }
                        .cornerRadius(16)
                        .clipped()
                    } else {
                        placeholderCover
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Text(audiobook.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                // Chapter navigation (if chapters exist)
                if !audiobook.chapters.isEmpty, let chapter = playerManager.currentChapter {
                    HStack(spacing: 16) {
                        // Previous chapter button
                        Button(action: {
                            playerManager.previousChapter()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }

                        // Chapter button
                        Button(action: {
                            showChaptersList = true
                        }) {
                            Text(chapter.title)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(8)
                        }

                        // Next chapter button
                        Button(action: {
                            playerManager.nextChapter()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                Text("No audiobook selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 4) {
                // Scrubber
                if let currentChapter = playerManager.currentChapter {
                    // Chapter-based scrubber
                    CustomProgressBar(
                        value: playerManager.currentTime,
                        range: currentChapter.startTime...currentChapter.endTime,
                        onSeek: { playerManager.seek(to: $0) },
                        isDisabled: playerManager.currentAudiobook == nil
                    )
                    
                    // Time labels (chapter-relative)
                    ZStack {
                        let remainingSeconds = playerManager.duration - playerManager.currentTime
                        let adjustedRemaining = remainingSeconds / Double(playerManager.playbackSpeed)
                        Text(formatRemainingTime(adjustedRemaining, speed: playerManager.playbackSpeed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text((playerManager.currentTime - currentChapter.startTime).formattedTime())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text("-" + (currentChapter.endTime - playerManager.currentTime).formattedTime())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    // Book-wide scrubber (no chapters)
                    CustomProgressBar(
                        value: playerManager.currentTime,
                        range: 0...max(playerManager.duration, 0.1),
                        onSeek: { playerManager.seek(to: $0) },
                        isDisabled: playerManager.currentAudiobook == nil
                    )
                    
                    // Time labels (book-relative)
                    ZStack {
                        let remainingSeconds = playerManager.duration - playerManager.currentTime
                        let adjustedRemaining = remainingSeconds / Double(playerManager.playbackSpeed)
                        Text(formatRemainingTime(adjustedRemaining, speed: playerManager.playbackSpeed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(playerManager.currentTime.formattedTime())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text("-" + (playerManager.duration - playerManager.currentTime).formattedTime())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()

            // Playback controls
            HStack(spacing: 24) {
                // Playback speed
                Button {
                    showSpeedPicker = true
                } label: {
                    Text("\(playerManager.playbackSpeed, specifier: "%.2f")x")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(width: 50)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
                .disabled(playerManager.currentAudiobook == nil)

                // Skip backward 15s
                Button(action: {
                    playerManager.skipBackward(15)
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .disabled(playerManager.currentAudiobook == nil)

                // Play/Pause
                Button(action: {
                    playerManager.togglePlayPause()
                }) {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.primary)
                }
                .disabled(playerManager.currentAudiobook == nil)

                // Skip forward 30s
                Button(action: {
                    playerManager.skipForward(30)
                }) {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .disabled(playerManager.currentAudiobook == nil)

                // Sleep timer
                Button {
                    showSleepTimer = true
                } label: {
                    if let remaining = playerManager.sleepTimerRemaining {
                        Text(formatTimerRemaining(remaining))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(width: 50)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)
                    } else {
                        Text("Sleep")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(width: 50)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .disabled(playerManager.currentAudiobook == nil)
            }
            .padding(.bottom, 40)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: $showChaptersList) {
            if let audiobook = playerManager.currentAudiobook {
                ChaptersListView(
                    chapters: audiobook.chapters,
                    currentChapter: playerManager.currentChapter,
                    onChapterSelect: { chapter in
                        playerManager.seekToChapter(chapter)
                    }
                )
            }
        }
        .sheet(isPresented: $showSpeedPicker) {
            SpeedPickerView(
                currentSpeed: playerManager.playbackSpeed,
                onSpeedSelect: { speed in
                    playerManager.setPlaybackSpeed(speed)
                    showSpeedPicker = false
                }
            )
            .presentationDetents([.height(365)])
        }
        .sheet(isPresented: $showSleepTimer) {
            let hasChapters = !(playerManager.currentAudiobook?.chapters.isEmpty ?? true) && playerManager.currentChapter != nil
            SleepTimerView(
                hasChapters: hasChapters,
                onTimerSelect: { option in
                    switch option {
                    case .off:
                        playerManager.setSleepTimer(minutes: 0)
                    case .minutes(let mins):
                        playerManager.setSleepTimer(minutes: mins)
                    case .endOfChapters(let count):
                        playerManager.setSleepTimerEndOfChapters(count: count)
                    }
                    showSleepTimer = false
                }
            )
            .presentationDetents([.height(hasChapters ? 365 : 265)])
        }
        .alert("Playback Error", isPresented: .constant(playerManager.playbackError != nil)) {
            Button("OK", role: .cancel) {
                playerManager.playbackError = nil
            }
        } message: {
            if let error = playerManager.playbackError {
                Text(error)
            }
        }
    }

    private func formatTimerRemaining(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }

    private func formatRemainingTime(_ timeInSeconds: Double, speed: Float) -> String {
        let totalSeconds = Int(timeInSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        var parts: [String] = []

        if hours > 0 {
            parts.append("\(hours)h")
        }

        if minutes > 0 || hours == 0 {
            parts.append("\(minutes)m")
        }

        let timeString = parts.joined(separator: " ")
        let speedString = String(format: "%.2fx", speed)

        return "\(timeString) left (\(speedString))"
    }

    private var placeholderCover: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))

                Image(systemName: "book.fill")
                    .font(.system(size: geometry.size.width * 0.27))
                    .foregroundColor(.gray)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SpeedPickerView: View {
    let currentSpeed: Float
    let onSpeedSelect: (Float) -> Void
    @Environment(\.dismiss) private var dismiss

    let speeds: [Float] = [1.75, 1.5, 1.35, 1.2, 1.0, 0.75]

    var body: some View {
        NavigationView {
            List {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        onSpeedSelect(speed)
                    } label: {
                        HStack {
                            Text(String(format: "%.2fx", speed))
                                .foregroundColor(.primary)
                            Spacer()
                            if abs(currentSpeed - speed) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(speed == 0.75 ? .hidden : .visible, edges: speed == 1.75 ? .bottom : .all)
                }
            }
            .padding(.top, 24)
            .listStyle(.plain)
            .scrollDisabled(true)
        }
        .presentationDragIndicator(.hidden)
    }
}

enum SleepTimerOption {
    case off
    case minutes(Int)
    case endOfChapters(Int)
}

struct SleepTimerView: View {
    let hasChapters: Bool
    let onTimerSelect: (SleepTimerOption) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Button {
                    onTimerSelect(.off)
                } label: {
                    HStack {
                        Text("Off")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onTimerSelect(.minutes(30))
                } label: {
                    HStack {
                        Text("30 minutes")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onTimerSelect(.minutes(45))
                } label: {
                    HStack {
                        Text("45 minutes")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onTimerSelect(.minutes(60))
                } label: {
                    HStack {
                        Text("60 minutes")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(hasChapters ? .visible : .hidden, edges: hasChapters ? .all : .bottom)

                if hasChapters {
                    Button {
                        onTimerSelect(.endOfChapters(1))
                    } label: {
                        HStack {
                            Text("End of Chapter")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onTimerSelect(.endOfChapters(2))
                    } label: {
                        HStack {
                            Text("End of 2 Chapters")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden, edges: .bottom)
                }
            }
            .padding(.top, 24)
            .listStyle(.plain)
            .scrollDisabled(true)
        }
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    AudioPlayerView(playerManager: AudioPlayerManager(), onCollapse: {})
}
