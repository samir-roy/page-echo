//
//  AudiobookListView.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import SwiftUI
import SwiftData
import Combine

struct AudiobookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var audiobooks: [Audiobook]
    @ObservedObject var playerManager: AudioPlayerManager
    @Binding var showingAddBook: Bool
    var onBookSelect: (Audiobook) -> Void

    @State private var bookToDelete: IndexSet?

    // most recently played first
    private var sortedAudiobooks: [Audiobook] {
        audiobooks.sorted { book1, book2 in
            guard let date1 = book1.lastPlayedDate else { return false }
            guard let date2 = book2.lastPlayedDate else { return true }
            return date1 > date2
        }
    }

    var body: some View {
        List {
            ForEach(sortedAudiobooks, id: \.id) { audiobook in
                AudiobookRow(audiobook: audiobook, playerManager: playerManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onBookSelect(audiobook)
                    }
            }
            .onDelete(perform: deleteAudiobooks)

            // Add book button at the end of the list
            Button(action: {
                showingAddBook = true
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .listRowSeparator(.hidden, edges: .bottom)
        }
        .listStyle(.plain)
        .alert("Delete Audiobook", isPresented: .constant(bookToDelete != nil)) {
            Button("Cancel", role: .cancel) {
                bookToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let offsets = bookToDelete {
                    confirmDelete(at: offsets)
                }
                bookToDelete = nil
            }
        } message: {
            if let offsets = bookToDelete, let index = offsets.first {
                Text("Are you sure you want to delete \"\(sortedAudiobooks[index].title)\"? This will also delete the downloaded file.")
            }
        }
    }

    private func deleteAudiobooks(at offsets: IndexSet) {
        bookToDelete = offsets
    }

    private func confirmDelete(at offsets: IndexSet) {
        for index in offsets {
            let audiobook = sortedAudiobooks[index]

            // If the deleted book is currently playing, stop it
            if playerManager.currentAudiobook?.id == audiobook.id {
                playerManager.currentAudiobook = nil
                playerManager.isPlaying = false
                playerManager.currentTime = 0
                playerManager.duration = 0
            }

            // Delete the downloaded file
            if let filename = audiobook.localFilePath {
                let documentsPath = FileManager.documentsDirectory
                let fileURL = documentsPath.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }

            modelContext.delete(audiobook)
        }
    }
}

struct AudiobookRow: View {
    let audiobook: Audiobook
    let playerManager: AudioPlayerManager

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            // Cover art - use .id() to maintain stable identity
            Group {
                if let coverData = audiobook.coverImageData,
                   let uiImage = UIImage(data: coverData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 90)
                        .cornerRadius(12)
                        .clipped()
                } else if let coverURL = audiobook.coverImageURL,
                          let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholderCover
                    }
                    .frame(width: 90, height: 90)
                    .cornerRadius(12)
                    .clipped()
                } else {
                    placeholderCover
                }
            }
            .id("cover-\(audiobook.id)")

            // Title and progress
            VStack(alignment: .leading, spacing: 6) {
                Text(audiobook.title)
                    .font(.title3)
                    .lineLimit(2)

                Text("\(Int(audiobook.percentComplete))% complete")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("\(audiobook.currentPosition.formattedTime()) / \(audiobook.duration.formattedTime())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Animated histogram - only show if this book is currently playing
            PlayingIndicator(
                audiobookID: audiobook.id,
                playerManager: playerManager
            )
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] }
    }

    private var placeholderCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 90, height: 90)

            Image(systemName: "book.fill")
                .font(.title)
                .foregroundColor(.gray)
        }
    }
}

// Wrapper view that only observes playing state for this specific audiobook
struct PlayingIndicator: View {
    let audiobookID: UUID
    @ObservedObject var playerManager: AudioPlayerManager

    var body: some View {
        // Only show histogram if this specific book is currently playing
        if playerManager.currentAudiobook?.id == audiobookID && playerManager.isPlaying {
            AnimatedHistogram()
                .id(audiobookID) // Maintain stable identity
        }
    }
}

struct AnimatedHistogram: View {
    @State private var barHeights: [CGFloat] = [0.3, 0.5, 0.7, 0.4, 0.6]
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 3, height: maxHeight(for: index) * barHeights[index])
            }
        }
        .frame(width: 35, height: 30)
        .onAppear {
            isAnimating = true
            animateBars()
        }
        .onDisappear {
            isAnimating = false
        }
    }

    private func maxHeight(for index: Int) -> CGFloat {
        // First and last bars are 50% height
        return (index == 0 || index == 4) ? 12 : 24
    }

    private func animateBars() {
        guard isAnimating else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            barHeights = (0..<5).map { _ in CGFloat.random(in: 0.3...1.0) }
        }

        // Schedule next animation cycle - closure captures self implicitly
        // This is safe for SwiftUI views (structs) as they are value types
        // The isAnimating check prevents continued recursion after view disappears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.animateBars()
        }
    }
}

#Preview {
    AudiobookListView(
        playerManager: AudioPlayerManager(),
        showingAddBook: .constant(false),
        onBookSelect: { _ in }
    )
    .modelContainer(for: Audiobook.self, inMemory: true)
}
