import SwiftUI
import AVFoundation
import CoreText
import Combine

nonisolated enum ExportQuality: String, CaseIterable, Identifiable, Sendable {
    case small, balanced, high
    var id: String { rawValue }
    var label: String {
        switch self { case .small: "Small · 540p"; case .balanced: "Balanced · 720p"; case .high: "High · 1080p" }
    }
    var size: CGSize {
        switch self { case .small: CGSize(width: 960, height: 540); case .balanced: CGSize(width: 1280, height: 720); case .high: CGSize(width: 1920, height: 1080) }
    }
    var preset: String {
        switch self { case .small: AVAssetExportPreset960x540; case .balanced: AVAssetExportPreset1280x720; case .high: AVAssetExportPreset1920x1080 }
    }
}

nonisolated enum VideoExportError: LocalizedError {
    case invalidMovie, titleTooLong, writer, timeout
    var errorDescription: String? {
        switch self {
        case .invalidMovie: "This recording could not be exported. Check that its video file is available."
        case .titleTooLong: "The question is too long for a readable title card. Shorten its text before exporting."
        case .writer: "The video encoder could not create the export."
        case .timeout: "The video encoder stopped responding. Try exporting again."
        }
    }
}

nonisolated enum TitleMovie {
    static func pixelBuffer(text: String, label: String, size: CGSize) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { throw VideoExportError.writer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw VideoExportError.writer }
        context.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let margin = size.width * 0.07
        let available = CGSize(width: size.width - margin * 2, height: size.height * 0.62)
        var fontSize = size.height / 15
        var setter: CTFramesetter?
        var measured = CGSize.zero
        while fontSize >= 14 {
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)]
            let candidate = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            measured = CTFramesetterSuggestFrameSizeWithConstraints(candidate, CFRange(location: 0, length: 0), nil,
                CGSize(width: available.width, height: .greatestFiniteMagnitude), nil)
            if measured.height <= available.height { setter = candidate; break }
            fontSize -= 2
        }
        guard let setter else { throw VideoExportError.titleTooLong }
        let bodyPath = CGPath(rect: CGRect(x: margin, y: (size.height - measured.height) / 2,
                                          width: available.width, height: measured.height + 4), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), bodyPath, nil), context)
        let heading = NSAttributedString(string: label.uppercased(), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size.height / 32, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 1)])
        let headingSetter = CTFramesetterCreateWithAttributedString(heading)
        let headingPath = CGPath(rect: CGRect(x: margin, y: size.height * 0.83, width: available.width, height: size.height * 0.08), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(headingSetter, CFRange(location: 0, length: 0), headingPath, nil), context)
        return buffer
    }

    static func write(text: String, label: String, size: CGSize, to url: URL, seconds: Double = 3) async throws {
        let buffer = try pixelBuffer(text: text, label: label, size: size)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw VideoExportError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoExportError.writer }
        writer.startSession(atSourceTime: .zero)
        do {
            let frames = max(1, Int(seconds * 30))
            for frame in 0..<frames {
                let deadline = Date().addingTimeInterval(15)
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    guard writer.status == .writing else { throw writer.error ?? VideoExportError.writer }
                    guard Date() < deadline else { throw VideoExportError.timeout }
                    try await Task.sleep(for: .milliseconds(5))
                }
                try Task.checkCancellation()
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                    throw writer.error ?? VideoExportError.writer
                }
            }
            writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? VideoExportError.writer }
        } catch { writer.cancelWriting(); throw error }
    }
}

@MainActor
final class VideoExporter: ObservableObject {
    @Published var progress = 0.0
    @Published var phase = "Preparing title card…"
    private var session: AVAssetExportSession?
    func cancel() { session?.cancelExport() }

    func export(source: URL, question: String, label: String, quality: ExportQuality, destination: URL) async throws {
        progress = 0
        phase = "Preparing title card…"
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory); session = nil }
        let titleURL = directory.appending(path: "title.mov")
        try await TitleMovie.write(text: question, label: label, size: quality.size, to: titleURL)
        try Task.checkCancellation()
        let original = AVURLAsset(url: source), title = AVURLAsset(url: titleURL)
        guard let sourceTrack = try await original.loadTracks(withMediaType: .video).first,
              let titleTrack = try await title.loadTracks(withMediaType: .video).first else { throw VideoExportError.invalidMovie }
        let originalDuration = try await original.load(.duration)
        let titleDuration = try await title.load(.duration)
        guard originalDuration.seconds.isFinite, originalDuration.seconds > 0 else { throw VideoExportError.invalidMovie }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoExportError.writer }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: titleDuration), of: titleTrack, at: .zero)
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: originalDuration), of: sourceTrack, at: titleDuration)
        if let sourceAudio = try await original.loadTracks(withMediaType: .audio).first,
           let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let range = try await sourceAudio.load(.timeRange)
            let usable = CMTimeRangeGetIntersection(range, otherRange: CMTimeRange(start: .zero, duration: originalDuration))
            try audio.insertTimeRange(usable, of: sourceAudio, at: titleDuration + usable.start)
        }
        var first = AVVideoCompositionInstruction.Configuration()
        first.timeRange = CMTimeRange(start: .zero, duration: titleDuration)
        var firstLayer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: video)
        firstLayer.setTransform(.identity, at: .zero)
        first.layerInstructions = [AVVideoCompositionLayerInstruction(configuration: firstLayer)]
        var second = AVVideoCompositionInstruction.Configuration()
        second.timeRange = CMTimeRange(start: titleDuration, duration: originalDuration)
        second.backgroundColor = CGColor(gray: 0, alpha: 1)
        let transform = try await sourceTrack.load(.preferredTransform)
        let natural = try await sourceTrack.load(.naturalSize)
        let bounds = CGRect(origin: .zero, size: natural).applying(transform)
        guard bounds.width > 0, bounds.height > 0 else { throw VideoExportError.invalidMovie }
        let factor = min(quality.size.width / bounds.width, quality.size.height / bounds.height)
        let fitted = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(translationX: (quality.size.width - bounds.width * factor) / 2,
                                             y: (quality.size.height - bounds.height * factor) / 2))
        var secondLayer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: video)
        secondLayer.setTransform(fitted, at: titleDuration)
        second.layerInstructions = [AVVideoCompositionLayerInstruction(configuration: secondLayer)]
        let videoComposition = AVVideoComposition(configuration: .init(
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [AVVideoCompositionInstruction(configuration: first), AVVideoCompositionInstruction(configuration: second)],
            renderSize: quality.size))
        guard let exporter = AVAssetExportSession(asset: composition, presetName: quality.preset) else { throw VideoExportError.writer }
        session = exporter
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        phase = "Exporting video…"
        let monitor = Task {
            for await state in exporter.states(updateInterval: 0.2) {
                if case .exporting(let value) = state { progress = value.fractionCompleted }
            }
        }
        defer { monitor.cancel() }
        try Task.checkCancellation()
        try await exporter.export(to: destination, as: .mp4)
        progress = 1
    }
}

struct VideoExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exportQuality") private var qualityValue = ExportQuality.balanced.rawValue
    @StateObject private var exporter = VideoExporter()
    @State private var work: Task<Void, Never>?
    @State private var working = false
    @State private var error: String?
    @State private var finished = false
    let take: Take
    let question: String
    let groupNumber: Int
    let questionNumber: Int
    let takeNumber: Int
    let setTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export Take").font(.title2.bold())
            Text(question).lineLimit(4).foregroundStyle(.secondary)
            Picker("Video quality", selection: $qualityValue) {
                ForEach(ExportQuality.allCases) { Text($0.label).tag($0.rawValue) }
            }.disabled(working)
            Text("Adds a three-second question title card, then plays the full answer. Exports an H.264 MP4.")
                .font(.caption).foregroundStyle(.secondary)
            if working { ProgressView(exporter.phase, value: exporter.progress) }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            if finished { Label("Video exported", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack {
                Button(working ? "Cancel Export" : "Done") {
                    if working { work?.cancel(); exporter.cancel() } else { dismiss() }
                }
                Spacer()
                Button("Export…") { chooseDestination() }.disabled(working).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 500)
        .interactiveDismissDisabled(working)
        .onDisappear { work?.cancel(); exporter.cancel() }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        let safeTitle = String(setTitle.prefix(70)).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = String(format: "%@ - G%02d Q%02d - Take %02d.mp4", safeTitle, groupNumber, questionNumber, takeNumber)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        working = true; error = nil; finished = false
        work = Task {
            let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mp4")
            defer { working = false; try? FileManager.default.removeItem(at: temporary) }
            do {
                let source = try AssetStorage.applicationStorage().url(for: take.videoPath)
                try await exporter.export(source: source, question: question, label: "Question \(groupNumber).\(questionNumber)",
                                          quality: ExportQuality(rawValue: qualityValue) ?? .balanced, destination: temporary)
                try Task.checkCancellation()
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                // Replace only after encoding succeeds; cancellation preserves an existing export.
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                } else { try FileManager.default.copyItem(at: temporary, to: destination) }
                finished = true
            } catch is CancellationError { error = "Export cancelled." }
            catch { self.error = Task.isCancelled ? "Export cancelled." : error.localizedDescription }
        }
    }
}
