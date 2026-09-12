import Foundation
import SwiftData
import Testing
@testable import OuterView

@MainActor
struct RecordingStoreTests {
    @Test func journalMakesTakeSaveIdempotentAndProtectsMedia() throws {
        let container = try ModelContainer(for: TrainingLibrary.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let library = TrainingLibrary(context: context)
        let draft = SetDraft.sample
        try library.save(draft)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = AssetStorage(root: root.appending(path: "Assets"))
        let recordings = RecordingStore(context: context, assets: assets)
        let journal = try recordings.prepare(setID: draft.id, questionID: draft.groups[0].questions[0].id)
        try Data("movie bytes".utf8).write(to: recordings.movieURL(journal.id))
        // Simulate a crash after moving media but before inserting its database row.
        let final = try assets.url(for: journal.relativePath)
        try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: recordings.movieURL(journal.id), to: final)
        try library.cleanupAssets(assets)
        #expect(FileManager.default.fileExists(atPath: final.path))
        try recordings.save(journal, duration: 10)
        try recordings.save(journal, duration: 10)
        #expect(try context.fetchCount(FetchDescriptor<Take>()) == 1)
        #expect(!FileManager.default.fileExists(atPath: recordings.journalURL(journal.id).path))
        #expect(try context.fetch(FetchDescriptor<Take>()).first?.question?.id == draft.groups[0].questions[0].id)
    }
}
