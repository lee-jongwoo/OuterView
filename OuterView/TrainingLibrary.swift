import Foundation
import SwiftData

@Model
final class TrainingSet {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var lastOpenedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \PassageGroup.trainingSet)
    var items: [PassageGroup] = []

    init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}

@Model
final class PassageGroup {
    @Attribute(.unique) var id: UUID
    var label: String
    var imagePath: String?
    var order: Int
    var trainingSet: TrainingSet?
    @Relationship(deleteRule: .cascade, inverse: \Question.passageGroup)
    var questions: [Question] = []

    init(id: UUID = UUID(), label: String, order: Int) {
        self.id = id
        self.label = label
        self.order = order
    }
}

@Model
final class Question {
    @Attribute(.unique) var id: UUID
    var text: String
    var order: Int
    var passageGroup: PassageGroup?
    @Relationship(deleteRule: .cascade, inverse: \Take.question)
    var takes: [Take] = []

    init(id: UUID = UUID(), text: String, order: Int) {
        self.id = id
        self.text = text
        self.order = order
    }
}

@Model
final class Take {
    @Attribute(.unique) var id: UUID
    var videoPath: String
    var recordedAt: Date
    var durationSeconds: Double
    var question: Question?

    init(videoPath: String, durationSeconds: Double, recordedAt: Date = Date()) {
        id = UUID()
        self.videoPath = videoPath
        self.durationSeconds = durationSeconds
        self.recordedAt = recordedAt
    }
}

/// All paths in the database are relative to this app-owned asset directory.
struct AssetStorage {
    let root: URL

    static func applicationStorage() throws -> AssetStorage {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
        return AssetStorage(root: support.appending(path: "OuterView/Assets", directoryHint: .isDirectory))
    }

    func url(for path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LibraryError.invalidAssetPath
        }
        let destination = root.appending(path: path).standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
        guard destination.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else {
            throw LibraryError.invalidAssetPath
        }
        return destination
    }

    func write(_ data: Data, setID: UUID, kind: String, extension suffix: String) throws -> String {
        guard ["images", "videos"].contains(kind), ["png", "jpg", "mov", "mp4"].contains(suffix) else {
            throw LibraryError.invalidAssetPath
        }
        let path = "\(setID.uuidString)/\(kind)/\(UUID().uuidString).\(suffix)"
        let destination = try url(for: path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return path
    }

    /// Run only after a successful database save (or at startup). A crash between
    /// database deletion and file cleanup is repaired on the next successful sweep.
    func removeUnreferenced(keeping paths: Set<String>) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return }
        let retained = try Set(paths.map { try url(for: $0).standardizedFileURL.path })
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            errorHandler: { _, error in enumerationError = error; return false }) else { return }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true && !retained.contains(file.standardizedFileURL.path) {
                try manager.removeItem(at: file)
            }
        }
        if let enumerationError { throw enumerationError }
    }
}

enum LibraryError: LocalizedError {
    case invalidDraft, invalidAssetPath
    var errorDescription: String? {
        switch self {
        case .invalidDraft: "Each set needs a title, a group, and nonempty questions."
        case .invalidAssetPath: "The asset path is outside the managed library or has an unsupported format."
        }
    }
}

@MainActor
struct TrainingLibrary {
    static let schema = Schema([TrainingSet.self, PassageGroup.self, Question.self, Take.self])
    let context: ModelContext

    func save(_ draft: SetDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.groups.isEmpty,
              draft.groups.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !$0.questions.isEmpty && $0.questions.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }) else {
            throw LibraryError.invalidDraft
        }
        do {
            let existing = try context.fetch(FetchDescriptor<TrainingSet>()).first { $0.id == draft.id }
            let set = existing ?? TrainingSet(id: draft.id, title: draft.title, createdAt: draft.createdAt)
            if existing == nil { context.insert(set) }
            set.title = draft.title
            // Opening a set, not editing it, owns lastOpenedAt.
            let groupIDs = Set(draft.groups.map(\.id))
            for removed in set.items where !groupIDs.contains(removed.id) { context.delete(removed) }
            set.items.removeAll { !groupIDs.contains($0.id) }
            for (order, value) in draft.groups.enumerated() {
                let group = set.items.first { $0.id == value.id } ?? PassageGroup(id: value.id, label: value.label, order: order)
                if group.trainingSet == nil { set.items.append(group) }
                group.label = value.label
                group.order = order
                group.imagePath = value.imagePath
                let questionIDs = Set(value.questions.map(\.id))
                for removed in group.questions where !questionIDs.contains(removed.id) { context.delete(removed) }
                group.questions.removeAll { !questionIDs.contains($0.id) }
                for (questionOrder, questionValue) in value.questions.enumerated() {
                    let question = group.questions.first { $0.id == questionValue.id } ?? Question(id: questionValue.id, text: questionValue.text, order: questionOrder)
                    if question.passageGroup == nil { group.questions.append(question) }
                    question.text = questionValue.text
                    question.order = questionOrder
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func markOpened(_ id: UUID) throws {
        do {
            if let set = try context.fetch(FetchDescriptor<TrainingSet>()).first(where: { $0.id == id }) {
                set.lastOpenedAt = Date()
                try context.save()
            }
        } catch { context.rollback(); throw error }
    }

    func delete(_ id: UUID) throws {
        do {
            if let set = try context.fetch(FetchDescriptor<TrainingSet>()).first(where: { $0.id == id }) {
                context.delete(set)
                try context.save()
            }
        } catch { context.rollback(); throw error }
    }

    func cleanupAssets(_ storage: AssetStorage) throws {
        let images = try context.fetch(FetchDescriptor<PassageGroup>()).compactMap(\.imagePath)
        let videos = try context.fetch(FetchDescriptor<Take>()).map(\.videoPath)
        try storage.removeUnreferenced(keeping: Set(images + videos))
    }
}

extension SetDraft {
    init(model: TrainingSet) {
        id = model.id
        title = model.title
        createdAt = model.createdAt
        lastOpenedAt = model.lastOpenedAt
        groups = model.items.sorted { $0.order < $1.order }.map { group in
            GroupDraft(id: group.id, label: group.label, imagePath: group.imagePath,
                       questions: group.questions.sorted { $0.order < $1.order }.map { QuestionDraft(id: $0.id, text: $0.text) })
        }
    }
}
