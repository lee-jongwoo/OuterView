import Foundation
import AVFoundation
import SwiftData

struct RecordingJournal: Codable, Identifiable {
    let id: UUID
    let setID: UUID
    let questionID: UUID
    let recordedAt: Date
    let relativePath: String
}

/// A small journal protects completed media across app crashes and failed DB saves.
@MainActor
struct RecordingStore {
    let context: ModelContext
    let assets: AssetStorage
    var pendingRoot: URL { assets.root.deletingLastPathComponent().appending(path: "PendingRecordings") }
    func journalURL(_ id: UUID) -> URL { pendingRoot.appending(path: id.uuidString + ".json") }
    func movieURL(_ id: UUID) -> URL { pendingRoot.appending(path: id.uuidString + ".mov") }

    func prepare(setID: UUID, questionID: UUID) throws -> RecordingJournal {
        let id = UUID()
        let journal = RecordingJournal(id: id, setID: setID, questionID: questionID, recordedAt: Date(),
            relativePath: "\(setID.uuidString)/videos/\(id.uuidString).mov")
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: journalURL(id), options: .atomic)
        return journal
    }

    func save(_ journal: RecordingJournal, duration: Double) throws {
        let destination = try assets.url(for: journal.relativePath)
        let source = movieURL(journal.id)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: source, to: destination)
        }
        do {
            if try context.fetch(FetchDescriptor<Take>()).contains(where: { $0.id == journal.id }) {
                try? FileManager.default.removeItem(at: journalURL(journal.id))
                return
            }
            guard let question = try context.fetch(FetchDescriptor<Question>()).first(where: { $0.id == journal.questionID }) else {
                throw RecordingStoreError.missingQuestion
            }
            let take = Take(videoPath: journal.relativePath, durationSeconds: duration, recordedAt: journal.recordedAt)
            take.id = journal.id
            question.takes.append(take)
            try context.save()
            try? FileManager.default.removeItem(at: journalURL(journal.id))
        } catch { context.rollback(); throw error }
    }

    func recover() async -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: pendingRoot, includingPropertiesForKeys: nil) else { return [] }
        var failures: [String] = []
        for url in urls where url.pathExtension == "json" {
            do {
                let journal = try JSONDecoder().decode(RecordingJournal.self, from: Data(contentsOf: url))
                let final = try assets.url(for: journal.relativePath)
                let source = FileManager.default.fileExists(atPath: final.path) ? final : movieURL(journal.id)
                // A crash before recording began leaves only a journal, not a take.
                guard FileManager.default.fileExists(atPath: source.path) else {
                    try FileManager.default.removeItem(at: url); continue
                }
                let duration = try await AVURLAsset(url: source).load(.duration).seconds
                guard duration.isFinite, duration > 0 else { throw RecordingStoreError.invalidMovie }
                try save(journal, duration: duration)
            } catch { failures.append(error.localizedDescription) }
        }
        return failures
    }

    func protectedPaths() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: pendingRoot.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: pendingRoot, includingPropertiesForKeys: nil)
        return try Set(urls.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(RecordingJournal.self, from: Data(contentsOf: $0)).relativePath
        })
    }
}

enum RecordingStoreError: LocalizedError {
    case missingQuestion, invalidMovie
    var errorDescription: String? {
        switch self {
        case .missingQuestion: "A recovered recording has no matching question. Its media has been kept in the library folder."
        case .invalidMovie: "An interrupted movie could not be read. Its file has been kept in the library folder."
        }
    }
}
