import Foundation
import SwiftData
import Testing
@testable import OuterView

@MainActor
struct OuterViewTests {
    private func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: TrainingLibrary.schema,
            configurations: [ModelConfiguration(schema: TrainingLibrary.schema, url: url, cloudKitDatabase: .none)])
    }

    @Test func librarySurvivesReopeningAndKeepsOrderedContent() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Library.store")
        var draft = SetDraft.sample
        draft.title = "Persistence check"
        draft.groups.reverse()
        let id = draft.id
        do {
            let store = try container(at: url)
            let context = ModelContext(store)
            context.autosaveEnabled = false
            let library = TrainingLibrary(context: context)
            try library.save(draft)
            try library.markOpened(id)
        }
        let reopened = try container(at: url)
        let saved = try ModelContext(reopened).fetch(FetchDescriptor<TrainingSet>())
        #expect(saved.count == 1)
        let loaded = SetDraft(model: try #require(saved.first))
        #expect(loaded.id == id)
        #expect(loaded.title == "Persistence check")
        #expect(loaded.lastOpenedAt != nil)
        #expect(loaded.groups.map(\.id) == draft.groups.map(\.id))
        #expect(loaded.groups.flatMap { $0.questions.map(\.text) } == draft.groups.flatMap { $0.questions.map(\.text) })
    }

    @Test func editsPreserveTakesAndDeletionCleansOnlyUnreferencedAssets() throws {
        let store = try ModelContainer(for: TrainingLibrary.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(store)
        context.autosaveEnabled = false
        let library = TrainingLibrary(context: context)
        var draft = SetDraft.sample
        try library.save(draft)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = AssetStorage(root: directory)
        let video = try assets.write(Data("take".utf8), setID: draft.id, kind: "videos", extension: "mov")
        let image = try assets.write(Data("passage".utf8), setID: draft.id, kind: "images", extension: "png")
        let questions = try context.fetch(FetchDescriptor<Question>())
        let originalID = draft.groups[0].questions[0].id
        let question = try #require(questions.first { $0.id == originalID })
        let take = Take(videoPath: video, durationSeconds: 4)
        question.takes.append(take)
        question.passageGroup?.imagePath = image
        try context.save()
        draft.groups[0].imagePath = image
        draft.groups[0].questions[0].text = "Edited question"
        draft.groups[0].questions.reverse()
        draft.groups.reverse()
        try library.save(draft)
        #expect(question.text == "Edited question")
        #expect(question.takes.first?.id == take.id)
        try library.cleanupAssets(assets)
        #expect(FileManager.default.fileExists(atPath: try assets.url(for: video).path))
        #expect(FileManager.default.fileExists(atPath: try assets.url(for: image).path))
        // Removing a question cascades its takes while retaining its group's image.
        let groupIndex = try #require(draft.groups.firstIndex { $0.questions.contains { $0.id == originalID } })
        draft.groups[groupIndex].questions.removeAll { $0.id == originalID }
        try library.save(draft)
        try library.cleanupAssets(assets)
        #expect(try context.fetchCount(FetchDescriptor<Take>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: try assets.url(for: video).path))
        #expect(FileManager.default.fileExists(atPath: try assets.url(for: image).path))
        try library.delete(draft.id)
        try library.cleanupAssets(assets)
        #expect(try context.fetchCount(FetchDescriptor<PassageGroup>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Question>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: try assets.url(for: image).path))
    }

    @Test func invalidDraftDoesNotMutateSavedSetAndPathsCannotEscape() throws {
        let store = try ModelContainer(for: TrainingLibrary.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(store)
        let library = TrainingLibrary(context: context)
        var draft = SetDraft.sample
        try library.save(draft)
        draft.title = ""
        #expect(throws: LibraryError.self) { try library.save(draft) }
        #expect(try context.fetch(FetchDescriptor<TrainingSet>()).first?.title == SetDraft.sample.title)
        let assets = AssetStorage(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        for path in ["../outside", "/absolute", "set/../../outside", "set//file"] {
            #expect(throws: LibraryError.self) { try assets.url(for: path) }
        }
    }
}
