import Foundation
import AppKit
import Testing
@testable import OuterView

@MainActor
struct TrainingArchiveTests {
    @Test func roundTripPreservesOrderAndCreatesFreshIdentities() throws {
        var draft = SetDraft.sample
        let assets = AssetStorage(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: assets.root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        draft.groups[0].imagePath = try assets.write(image, setID: draft.id, kind: "images", extension: "png")
        let archive = try TrainingArchive.export(draft, assets: assets)
        let imported = try TrainingArchive.decode(archive)
        #expect(imported.groups[0].imageData == image)
        #expect(imported.id != draft.id)
        #expect(imported.lastOpenedAt == nil)
        #expect(imported.title == draft.title)
        #expect(imported.groups.map(\.label) == draft.groups.map(\.label))
        #expect(imported.groups.flatMap { $0.questions.map(\.text) } == draft.groups.flatMap { $0.questions.map(\.text) })
        #expect(imported.groups[0].questions[0].id != draft.groups[0].questions[0].id)
    }
    @Test func archiveIsReadableByStandardUnzip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try StoredZIP.encode([("manifest.json", Data("{\"version\":1}".utf8))]).write(to: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
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
