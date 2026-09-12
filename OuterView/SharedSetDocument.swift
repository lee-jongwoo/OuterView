import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let outerview = UTType(exportedAs: "dev.jongwoo.outerview.training-set", conformingTo: .zip)
}

struct SharedSetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.outerview] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ArchiveError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
