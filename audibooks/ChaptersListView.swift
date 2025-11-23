//
//  ChaptersListView.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import SwiftUI

struct ChaptersListView: View {
    let chapters: [Chapter]
    let currentChapter: Chapter?
    let onChapterSelect: (Chapter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(chapters) { chapter in
                    Button(action: {
                        onChapterSelect(chapter)
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text(chapter.startTime.formattedTime())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if currentChapter?.id == chapter.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ChaptersListView(
        chapters: [
            Chapter(title: "Introduction", startTime: 0, duration: 300),
            Chapter(title: "Chapter 1: The Beginning", startTime: 300, duration: 600),
            Chapter(title: "Chapter 2: The Middle", startTime: 900, duration: 600)
        ],
        currentChapter: Chapter(title: "Introduction", startTime: 0, duration: 300),
        onChapterSelect: { _ in }
    )
}
