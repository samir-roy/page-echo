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
    @State private var hasLoadedLastBook = false
    @State private var isPlayerExpanded = false

    var body: some View {
        NavigationStack {
            AudiobookListView(
                playerManager: playerManager,
                showingAddBook: $showingAddBook,
                onBookSelect: { audiobook in
                    isPlayerExpanded = true
                    playerManager.loadAudiobook(audiobook)
                    if !playerManager.isPlaying {
                        playerManager.togglePlayPause()
                    }
                }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Page Echo")
                        .font(.headline)
                }
            }
        }
        .sheet(isPresented: $isPlayerExpanded) {
            AudioPlayerView(
                playerManager: playerManager,
                onCollapse: {
                    isPlayerExpanded = false
                }
            )
        }
        .sheet(isPresented: $showingAddBook) {
            AddBookView()
        }
        .onAppear {
            playerManager.setModelContext(modelContext)
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
}

#Preview {
    ContentView()
        .modelContainer(for: Audiobook.self, inMemory: true)
}
