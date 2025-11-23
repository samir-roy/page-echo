//
//  ContentView.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var audiobooks: [Audiobook]
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var showingAddBook = false
    @State private var showingBookSelection = false
    @State private var hasLoadedInitialBook = false

    var body: some View {
        AudioPlayerView(
            playerManager: playerManager,
            showingAddBook: $showingAddBook,
            onShowBookSelection: {
                showingBookSelection = true
            }
        )
        .sheet(isPresented: $showingBookSelection) {
            BookSelectionView(
                playerManager: playerManager,
                showingAddBook: $showingAddBook,
                onBookSelect: { audiobook in
                    playerManager.loadAudiobook(audiobook)
                    if !playerManager.isPlaying {
                        playerManager.togglePlayPause()
                    }
                }
            )
        }
        .sheet(isPresented: $showingAddBook) {
            AddBookView()
        }
        .onAppear {
            playerManager.setModelContext(modelContext)
            if !hasLoadedInitialBook {
                loadInitialBook()
                hasLoadedInitialBook = true
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background, .inactive:
                playerManager.pauseUIUpdates()
            case .active:
                playerManager.resumeUIUpdates()
            @unknown default:
                break
            }
        }
    }

    private func loadInitialBook() {
        // First, try to load the last played book
        if let lastPlayedID = UserDefaults.standard.lastPlayedAudiobookID,
           let uuid = UUID(uuidString: lastPlayedID),
           let lastPlayedBook = audiobooks.first(where: { $0.id == uuid }) {
            playerManager.loadAudiobook(lastPlayedBook)
            return
        }

        // If no last played book, load the most recently added book
        if let mostRecentBook = audiobooks.sorted(by: { book1, book2 in
            let date1 = book1.lastPlayedDate ?? Date.distantPast
            let date2 = book2.lastPlayedDate ?? Date.distantPast
            return date1 > date2
        }).first {
            playerManager.loadAudiobook(mostRecentBook)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Audiobook.self, inMemory: true)
}
