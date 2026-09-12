import Foundation
import Testing
@testable import OuterView

@MainActor
struct TrainingArchiveTests {
    @Test func roundTripPreservesOrderAndCreatesFreshIdentities() throws {
        let draft = SetDraft.sample
        let assets = AssetStorage(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let archive = try TrainingArchive.export(draft, assets: assets)
        let imported = try TrainingArchive.decode(archive)
        #expect(imported.id != draft.id)
        #expect(imported.lastOpenedAt == nil)
        #expect(imported.title == draft.title)
        #expect(imported.groups.map(\.label) == draft.groups.map(\.label))
        #expect(imported.groups.flatMap { $0.questions.map(\.text) } == draft.groups.flatMap { $0.questions.map(\.text) })
        #expect(imported.groups[0].questions[0].id != draft.groups[0].questions[0].id)
    }
    @Test func damagedOrUnsafeArchivesAreRejected() throws {
        let archive = try StoredZIP.encode([("manifest.json", Data("hello".utf8))])
        var damaged = archive
        damaged[45] ^= 0xff
        #expect(throws: ArchiveError.self) { try StoredZIP.decode(damaged) }
        let traversal = try StoredZIP.encode([("../escape", Data())])
        #expect(throws: ArchiveError.self) { try StoredZIP.decode(traversal) }
        let duplicates = try StoredZIP.encode([("same", Data()), ("same", Data())])
        #expect(throws: ArchiveError.self) { try StoredZIP.decode(duplicates) }
        for count in [0, 4, 21, archive.count - 1] {
            #expect(throws: ArchiveError.self) { try StoredZIP.decode(Data(archive.prefix(count))) }
        }
        let unsupported = TrainingManifest(version: 2, title: "Future", groups: [])
        #expect(throws: ArchiveError.self) {
            try TrainingArchive.decode(StoredZIP.encode([("manifest.json", JSONEncoder().encode(unsupported))]))
        }
    }
}
