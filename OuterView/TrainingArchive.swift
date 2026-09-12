import Foundation
import ImageIO

/// v1 uses standard ZIP entries with the STORE method. No extraction to disk is
/// needed: names, sizes, checksums, and the manifest are validated in memory.
nonisolated enum StoredZIP {
    static let maximumSize = 200 * 1024 * 1024
    static func crc(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) != 0 ? 0xedb88320 : 0) }
        }
        return value ^ 0xffffffff
    }
    static func encode(_ files: [(String, Data)]) throws -> Data {
        guard files.count <= 1001 else { throw ArchiveError.invalid }
        var local = Data(), central = Data()
        for (name, data) in files {
            let bytes = Data(name.utf8)
            guard data.count <= maximumSize, bytes.count < 65536 else { throw ArchiveError.tooLarge }
            let offset = local.count, checksum = crc(data)
            local.le(UInt32(0x04034b50)); local.le(UInt16(20)); local.le(UInt16(0x800)); local.le(UInt16(0))
            local.le(UInt16(0)); local.le(UInt16(0)); local.le(checksum)
            local.le(UInt32(data.count)); local.le(UInt32(data.count)); local.le(UInt16(bytes.count)); local.le(UInt16(0))
            local.append(bytes); local.append(data)
            central.le(UInt32(0x02014b50)); central.le(UInt16(20)); central.le(UInt16(20)); central.le(UInt16(0x800)); central.le(UInt16(0))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(checksum)
            central.le(UInt32(data.count)); central.le(UInt32(data.count)); central.le(UInt16(bytes.count))
            for _ in 0..<4 { central.le(UInt16(0)) }
            central.le(UInt32(0)); central.le(UInt32(offset)); central.append(bytes)
            guard local.count + central.count < maximumSize else { throw ArchiveError.tooLarge }
        }
        let offset = local.count
        local.append(central)
        local.le(UInt32(0x06054b50)); local.le(UInt16(0)); local.le(UInt16(0))
        local.le(UInt16(files.count)); local.le(UInt16(files.count))
        local.le(UInt32(central.count)); local.le(UInt32(offset)); local.le(UInt16(0))
        return local
    }
    static func decode(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22, data.count <= maximumSize else { throw ArchiveError.tooLarge }
        // Our portable format disallows ZIP comments, spanning, ZIP64, encryption,
        // and compressed entries. This keeps bounds and decompression risks explicit.
        let end = data.count - 22
        guard try data.u32(end) == 0x06054b50, try data.u16(end + 4) == 0, try data.u16(end + 6) == 0,
              try data.u16(end + 20) == 0 else { throw ArchiveError.invalid }
        let count = Int(try data.u16(end + 10))
        guard count <= 1001, count == Int(try data.u16(end + 8)) else { throw ArchiveError.invalid }
        let start = Int(try data.u32(end + 16)), centralSize = Int(try data.u32(end + 12))
        guard start + centralSize == end else { throw ArchiveError.invalid }
        var cursor = start, files: [String: Data] = [:], occupied = 0
        for _ in 0..<count {
            guard try data.u32(cursor) == 0x02014b50 else { throw ArchiveError.invalid }
            let flags = try data.u16(cursor + 8), method = try data.u16(cursor + 10)
            guard flags == 0x800 || flags == 0, method == 0 else { throw ArchiveError.unsupportedZIP }
            let size = Int(try data.u32(cursor + 24)), packed = Int(try data.u32(cursor + 20))
            let nameLength = Int(try data.u16(cursor + 28)), extra = Int(try data.u16(cursor + 30)), comment = Int(try data.u16(cursor + 32))
            guard size == packed, size <= maximumSize, try data.u16(cursor + 34) == 0,
                  (try data.u32(cursor + 38) >> 16) & 0xf000 != 0xa000 else { throw ArchiveError.invalid }
            let nameData = try data.bytes(cursor + 46, nameLength)
            guard let name = String(data: nameData, encoding: .utf8), !name.hasPrefix("/"), !name.contains("\\"),
                  !name.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  files[name] == nil else { throw ArchiveError.invalid }
            let local = Int(try data.u32(cursor + 42))
            guard local == occupied, try data.u32(local) == 0x04034b50,
                  try data.u16(local + 6) == flags, try data.u16(local + 8) == method,
                  try data.u32(local + 18) == packed, try data.u32(local + 22) == size else { throw ArchiveError.invalid }
            let localName = Int(try data.u16(local + 26)), localExtra = Int(try data.u16(local + 28))
            guard try data.bytes(local + 30, localName) == nameData else { throw ArchiveError.invalid }
            let payloadStart = local + 30 + localName + localExtra
            occupied = payloadStart + size
            guard occupied <= start else { throw ArchiveError.invalid }
            let payload = try data.bytes(payloadStart, size)
            guard crc(payload) == (try data.u32(cursor + 16)), try data.u32(local + 14) == data.u32(cursor + 16) else { throw ArchiveError.invalid }
            files[name] = payload
            cursor += 46 + nameLength + extra + comment
            guard cursor <= end else { throw ArchiveError.invalid }
        }
        guard cursor == end, occupied == start else { throw ArchiveError.invalid }
        return files
    }
}

private nonisolated extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
    func bytes(_ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= self.count, count <= self.count - offset else { throw ArchiveError.invalid }
        return subdata(in: offset..<(offset + count))
    }
    func u16(_ offset: Int) throws -> UInt16 {
        let value = try bytes(offset, 2)
        return UInt16(value[value.startIndex]) | UInt16(value[value.startIndex + 1]) << 8
    }
    func u32(_ offset: Int) throws -> UInt32 {
        UInt32(try u16(offset)) | UInt32(try u16(offset + 2)) << 16
    }
}

nonisolated enum ArchiveError: LocalizedError {
    case invalid, version, tooLarge, unsupportedZIP
    var errorDescription: String? {
        switch self {
        case .invalid: "This training-set file is damaged or has an invalid structure. Nothing was imported."
        case .version: "This training set requires a newer version of OuterView."
        case .tooLarge: "Training-set files must be under 200 MB and contain at most 1,000 groups."
        case .unsupportedZIP: "This ZIP encoding is not supported. Share the .outerview file directly as exported by OuterView."
        }
    }
}

nonisolated struct TrainingManifest: Codable {
    var version: Int
    var title: String
    var groups: [Group]
    struct Group: Codable {
        var label: String
        var order: Int
        var image: String?
        var questions: [Entry]
    }
    struct Entry: Codable { var text: String; var order: Int }
}

nonisolated enum TrainingArchive {
    static func export(_ draft: SetDraft, assets: AssetStorage) throws -> Data {
        var files: [(String, Data)] = []
        let groups = try draft.groups.enumerated().map { index, group in
            var path: String?
            if let source = group.imagePath {
                path = "images/\(index + 1).png"
                files.append((path!, try Data(contentsOf: assets.url(for: source))))
            }
            return TrainingManifest.Group(label: group.label, order: index, image: path,
                questions: group.questions.enumerated().map { TrainingManifest.Entry(text: $0.element.text, order: $0.offset) })
        }
        let manifest = TrainingManifest(version: 1, title: draft.title, groups: groups)
        files.insert(("manifest.json", try JSONEncoder().encode(manifest)), at: 0)
        return try StoredZIP.encode(files)
    }

    static func decode(_ data: Data) throws -> SetDraft {
        let files = try StoredZIP.decode(data)
        guard let json = files["manifest.json"], json.count < 5 * 1024 * 1024 else { throw ArchiveError.invalid }
        let manifest = try JSONDecoder().decode(TrainingManifest.self, from: json)
        guard manifest.version == 1 else { throw ArchiveError.version }
        guard validText(manifest.title), !manifest.groups.isEmpty, manifest.groups.count <= 1000,
              Set(manifest.groups.map(\.order)) == Set(0..<manifest.groups.count) else { throw ArchiveError.invalid }
        var used: Set<String> = ["manifest.json"]
        var questionCount = 0
        let groups = try manifest.groups.sorted { $0.order < $1.order }.map { group in
            questionCount += group.questions.count
            guard validText(group.label), !group.questions.isEmpty, questionCount <= 5000,
                  group.questions.allSatisfy({ validText($0.text) }),
                  Set(group.questions.map(\.order)) == Set(0..<group.questions.count) else { throw ArchiveError.invalid }
            var image: Data?
            if let path = group.image {
                guard path.hasPrefix("images/"), path.hasSuffix(".png"), let bytes = files[path],
                      let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 10000, height <= 10000,
                      width * height <= 25_000_000, CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw ArchiveError.invalid }
                used.insert(path); image = bytes
            }
            return GroupDraft(label: group.label, imageData: image,
                questions: group.questions.sorted { $0.order < $1.order }.map { QuestionDraft(text: $0.text) })
        }
        guard used == Set(files.keys) else { throw ArchiveError.invalid }
        return SetDraft(title: manifest.title, groups: groups)
    }
    private static func validText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 100_000
    }
}
