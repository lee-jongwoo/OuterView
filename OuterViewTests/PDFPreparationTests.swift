import AppKit
import PDFKit
import SwiftData
import Testing
@testable import OuterView

@MainActor
struct PDFPreparationTests {
    @Test func cropMatchesRenderedPageAndPersists() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<100 {
            for x in 0..<100 { bitmap.setColor(NSColor(deviceRed: y < 50 ? 1 : 0, green: 0, blue: y < 50 ? 0 : 1, alpha: 1), atX: x, y: y) }
        }
        #expect(try #require(bitmap.colorAt(x: 10, y: 10)).redComponent > 0.9)
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.addRepresentation(bitmap)
        let data = try PassageCrop.png(image: image, selection: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.25))
        let cropped = try #require(NSBitmapImageRep(data: data))
        #expect(cropped.pixelsWide == 50)
        #expect(cropped.pixelsHigh == 25)
        let color = try #require(cropped.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
        #expect(color.redComponent > color.blueComponent + 0.5)
        #expect(throws: PDFPreparationError.self) { try PassageCrop.png(image: image, selection: .zero) }

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AssetStorage(root: directory)
        let container = try ModelContainer(for: TrainingLibrary.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let library = TrainingLibrary(context: container.mainContext)
        var draft = SetDraft.sample
        draft.groups[0].imageData = data
        try library.save(draft, storage: storage)
        let group = try #require(container.mainContext.fetch(FetchDescriptor<PassageGroup>()).first { $0.id == draft.groups[0].id })
        let path = try #require(group.imagePath)
        #expect(try Data(contentsOf: storage.url(for: path)) == data)
        // Replace a crop; cleanup must preserve the replacement and remove the old file.
        draft.groups[0].imageData = try PassageCrop.png(image: image, selection: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        try library.save(draft, storage: storage)
        try library.cleanupAssets(storage)
        #expect(!FileManager.default.fileExists(atPath: try storage.url(for: path).path))
        #expect(FileManager.default.fileExists(atPath: try storage.url(for: #require(group.imagePath)).path))
    }
}
