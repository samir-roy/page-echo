//
//  AddBookView.swift
//  audibooks
//
//  Created by Samir Roy on 11/1/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var bookTitle: String = ""
    @State private var audioURL: String = ""
    @State private var coverImageURL: String = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Book Information")) {
                    TextField("Book Title", text: $bookTitle)

                    TextField("Audio URL", text: $audioURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Cover Image URL (optional)", text: $coverImageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Button(action: addBook) {
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Downloading...")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Add Book")
                        }
                    }
                    .disabled(bookTitle.isEmpty || audioURL.isEmpty || isLoading)
                }
            }
            .navigationTitle("Add Audiobook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Download Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func addBook() {
        guard !bookTitle.isEmpty, !audioURL.isEmpty else { return }

        isLoading = true

        Task {
            // Convert sharing URLs to direct download URLs
            let directAudioURL = convertToDirectURL(audioURL)
            let directCoverURL = coverImageURL.isEmpty ? "" : convertToDirectURL(coverImageURL)

            // Download the audio file
            guard let audioUrl = URL(string: directAudioURL) else {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Invalid audio URL. Please check the URL and try again."
                    showError = true
                }
                return
            }

            let localFilePath = await downloadFile(from: audioUrl)

            guard let filePath = localFilePath else {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to download the audiobook. Please check your internet connection and the URL."
                    showError = true
                }
                return
            }

            var coverData: Data?

            // If no cover URL provided, try to extract from downloaded file
            if directCoverURL.isEmpty {
                coverData = await extractCoverArtFromLocalFile(filePath: filePath)
            } else {
                if let url = URL(string: directCoverURL) {
                    coverData = try? await URLSession.shared.data(from: url).0
                }
            }

            // Get audio duration and chapters from local file
            let duration = await getAudioDurationFromLocalFile(filePath: filePath)
            let chapters = await extractChaptersFromLocalFile(filePath: filePath)

            await MainActor.run {
                let newBook = Audiobook(
                    title: bookTitle,
                    coverImageURL: directCoverURL.isEmpty ? nil : directCoverURL,
                    coverImageData: coverData,
                    audioURL: directAudioURL,
                    localFilePath: filePath,
                    currentPosition: 0,
                    duration: duration,
                    chapters: chapters
                )

                modelContext.insert(newBook)

                isLoading = false
                dismiss()
            }
        }
    }

    private func downloadFile(from url: URL) async -> String? {
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)

            // Create a permanent location in Documents directory
            let documentsPath = FileManager.documentsDirectory
            let fileExtension = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let filename = "\(UUID().uuidString).\(fileExtension)"
            let destinationURL = documentsPath.appendingPathComponent(filename)

            // Move the downloaded file to permanent location
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            // Return only the filename, not the full path
            return filename
        } catch {
            print("Error downloading file: \(error)")
            return nil
        }
    }

    private func convertToDirectURL(_ urlString: String) -> String {
        var convertedURL = urlString

        // Google Drive conversion
        // From: https://drive.google.com/file/d/FILE_ID/view?usp=sharing
        // To: https://drive.google.com/uc?export=download&id=FILE_ID
        if urlString.contains("drive.google.com/file/d/") {
            if let fileIDRange = urlString.range(of: "/d/([^/]+)", options: .regularExpression) {
                let fileIDWithPrefix = String(urlString[fileIDRange])
                let fileID = fileIDWithPrefix.replacingOccurrences(of: "/d/", with: "")
                convertedURL = "https://drive.google.com/uc?export=download&id=\(fileID)"
            }
        }

        // Dropbox conversion
        // From: https://www.dropbox.com/...?dl=0
        // To: https://www.dropbox.com/...?dl=1
        if urlString.contains("dropbox.com") {
            convertedURL = urlString.replacingOccurrences(of: "?dl=0", with: "?dl=1")

            // Also handle the case where there's no dl parameter
            if !convertedURL.contains("?dl=") {
                convertedURL += convertedURL.contains("?") ? "&dl=1" : "?dl=1"
            }

            // Alternative: Convert to dl.dropboxusercontent.com
            convertedURL = convertedURL.replacingOccurrences(of: "www.dropbox.com", with: "dl.dropboxusercontent.com")
        }

        return convertedURL
    }

    private func extractCoverArtFromLocalFile(filePath: String) async -> Data? {
        let documentsPath = FileManager.documentsDirectory
        let url = documentsPath.appendingPathComponent(filePath)

        do {
            let asset = AVAsset(url: url)
            let metadata = try await asset.load(.metadata)

            for item in metadata {
                if let key = item.commonKey, key.rawValue == "artwork" {
                    if let data = try await item.load(.value) as? Data {
                        return data
                    }
                }
            }
        } catch {
            print("Error extracting cover art: \(error)")
        }

        return nil
    }

    private func getAudioDurationFromLocalFile(filePath: String) async -> Double {
        let documentsPath = FileManager.documentsDirectory
        let url = documentsPath.appendingPathComponent(filePath)

        do {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)

            return seconds
        } catch {
            print("Error getting duration: \(error)")
            return 0
        }
    }

    private func extractChaptersFromLocalFile(filePath: String) async -> [Chapter] {
        let documentsPath = FileManager.documentsDirectory
        let url = documentsPath.appendingPathComponent(filePath)

        do {
            let asset = AVAsset(url: url)

            // Get chapter metadata groups
            let languages = try await asset.load(.availableChapterLocales)

            guard let locale = languages.first else {
                // No embedded chapters, generate synthetic chapters
                return await generateSyntheticChapters(filePath: filePath)
            }

            let chapterGroups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyArtwork])

            var chapters: [Chapter] = []

            for (index, group) in chapterGroups.enumerated() {
                let timeRange = group.timeRange
                let startTime = CMTimeGetSeconds(timeRange.start)
                let duration = CMTimeGetSeconds(timeRange.duration)

                // Try to get chapter title
                var title = "Chapter \(index + 1)"
                if let titleItem = group.items.first(where: { $0.commonKey == .commonKeyTitle }) {
                    if let titleValue = try? await titleItem.load(.stringValue) {
                        title = titleValue
                    }
                }

                let chapter = Chapter(title: title, startTime: startTime, duration: duration)
                chapters.append(chapter)
            }

            // If no chapters were extracted, generate synthetic chapters
            if chapters.isEmpty {
                return await generateSyntheticChapters(filePath: filePath)
            }

            return chapters
        } catch {
            // On error, try to generate synthetic chapters
            return await generateSyntheticChapters(filePath: filePath)
        }
    }

    private func generateSyntheticChapters(filePath: String) async -> [Chapter] {
        // Get the total duration of the audio file
        let totalDuration = await getAudioDurationFromLocalFile(filePath: filePath)

        // If duration is 0 or very short, don't create chapters
        guard totalDuration > 0 else {
            return []
        }

        let chapterInterval: Double = 1800 // 30 minutes in seconds
        var chapters: [Chapter] = []

        var currentTime: Double = 0
        var chapterNumber = 1

        while currentTime < totalDuration {
            let remainingTime = totalDuration - currentTime
            let chapterDuration = min(chapterInterval, remainingTime)

            let chapter = Chapter(
                title: "Chapter \(chapterNumber)",
                startTime: currentTime,
                duration: chapterDuration
            )
            chapters.append(chapter)

            currentTime += chapterInterval
            chapterNumber += 1
        }

        return chapters
    }
}

#Preview {
    AddBookView()
        .modelContainer(for: Audiobook.self, inMemory: true)
}
