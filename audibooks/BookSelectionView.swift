//
//  BookSelectionView.swift
//  audibooks
//
//  Created by Samir Roy on 11/23/25.
//

import SwiftUI
import SwiftData

struct BookSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var audiobooks: [Audiobook]
    @ObservedObject var playerManager: AudioPlayerManager
    @Binding var showingAddBook: Bool
    var onBookSelect: (Audiobook) -> Void

    @State private var bookToDelete: Audiobook?
    @State private var showingLocalAddBook = false

    private var sortedAudiobooks: [Audiobook] {
        audiobooks.sorted { book1, book2 in
            guard let date1 = book1.lastPlayedDate else { return false }
            guard let date2 = book2.lastPlayedDate else { return true }
            return date1 > date2
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedAudiobooks, id: \.id) { audiobook in
                        BookGridItem(
                            audiobook: audiobook,
                            playerManager: playerManager,
                            onTap: {
                                onBookSelect(audiobook)
                                dismiss()
                            },
                            onLongPress: {
                                bookToDelete = audiobook
                            }
                        )
                    }

                    AddBookGridItem(onTap: {
                        showingLocalAddBook = true
                    })
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Delete Audiobook", isPresented: .constant(bookToDelete != nil)) {
            Button("Cancel", role: .cancel) {
                bookToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let audiobook = bookToDelete {
                    deleteAudiobook(audiobook)
                }
                bookToDelete = nil
            }
        } message: {
            if let audiobook = bookToDelete {
                Text("Are you sure you want to delete \"\(audiobook.title)\"? This will also delete the downloaded file.")
            }
        }
        .sheet(isPresented: $showingLocalAddBook) {
            AddBookView()
        }
    }

    private func deleteAudiobook(_ audiobook: Audiobook) {
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

struct BookGridItem: View {
    let audiobook: Audiobook
    let playerManager: AudioPlayerManager
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let coverData = audiobook.coverImageData,
                   let uiImage = UIImage(data: coverData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .cornerRadius(12)
                        .clipped()
                } else if let coverURL = audiobook.coverImageURL,
                          let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    } placeholder: {
                        placeholderCover
                    }
                    .cornerRadius(12)
                    .clipped()
                } else {
                    placeholderCover
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.4 : 1.0)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(pressing: { pressing in
                isPressed = pressing
            }) {
                onLongPress()
            }

            ProgressView(value: audiobook.percentComplete, total: 100.0)
                .progressViewStyle(.linear)
                .tint(.primary)
                .padding(.horizontal, 40)
        }
    }

    private var placeholderCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))

            Image(systemName: "book.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct AddBookGridItem: View {
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                onTap()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))

                    Image(systemName: "plus")
                        .font(.system(size: 50))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemBackground))
                }
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Rectangle())
            }

            ProgressView(value: 0.0, total: 100.0)
                .progressViewStyle(.linear)
                .tint(.primary)
                .padding(.horizontal, 40)
        }
    }
}

#Preview {
    BookSelectionView(
        playerManager: AudioPlayerManager(),
        showingAddBook: .constant(false),
        onBookSelect: { _ in }
    )
    .modelContainer(for: Audiobook.self, inMemory: true)
}
