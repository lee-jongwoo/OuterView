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
        case .titleTooLong: "The question is too long for a readable caption. Shorten its text before exporting."
        case .writer: "The video encoder could not create the export."
        case .timeout: "The video encoder stopped responding. Try exporting again."
        }
    }
}

nonisolated enum ExportCaption {
    static func image(text: String, label: String, size: CGSize) throws -> CGImage {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw VideoExportError.writer }
        let margin = size.width * 0.05
        let padding = size.height * 0.025
        let width = size.width - 2 * margin - 2 * padding
        let maxHeight = size.height * 0.24
        var fontSize = size.height * 0.042
        var setter: CTFramesetter?
        var measured = CGSize.zero
        while fontSize >= size.height * 0.03 {
            let candidate = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]))
            measured = CTFramesetterSuggestFrameSizeWithConstraints(candidate, CFRange(), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            if measured.height <= maxHeight { setter = candidate; break }
            fontSize -= 1
        }
        guard let setter else { throw VideoExportError.titleTooLong }
        let headingHeight = size.height * 0.034
        let bottom = size.height * 0.045
        let bodyHeight = ceil(measured.height) + 4
        let height = padding * 2 + bodyHeight + headingHeight + padding * 0.5
        let panel = CGRect(x: margin, y: bottom, width: size.width - margin * 2, height: height)
        context.setFillColor(CGColor(gray: 0.04, alpha: 0.78))
        context.addPath(CGPath(roundedRect: panel, cornerWidth: padding, cornerHeight: padding, transform: nil))
        context.fillPath()
        let body = CGPath(rect: CGRect(x: margin + padding, y: bottom + padding,
            width: width, height: bodyHeight), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), body, nil), context)
        let heading = CTFramesetterCreateWithAttributedString(NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size.height * 0.026, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.8, alpha: 1)]))
        let headingPath = CGPath(rect: CGRect(x: margin + padding, y: bottom + padding + bodyHeight + padding * 0.5,
            width: width, height: headingHeight), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(heading, CFRange(), headingPath, nil), context)
        guard let image = context.makeImage() else { throw VideoExportError.writer }
        return image
    }
}

@MainActor
final class VideoExporter: ObservableObject {
    @Published var progress = 0.0
    @Published var phase = "Preparing caption…"
    private var session: AVAssetExportSession?
    func cancel() { session?.cancelExport() }

    func export(source: URL, question: String, label: String, quality: ExportQuality, destination: URL) async throws {
        progress = 0
        phase = "Preparing caption…"
        defer { session = nil }
        let captionImage = try ExportCaption.image(text: question, label: label, size: quality.size)
        try Task.checkCancellation()
        let original = AVURLAsset(url: source)
        guard let sourceTrack = try await original.loadTracks(withMediaType: .video).first else { throw VideoExportError.invalidMovie }
        let originalDuration = try await original.load(.duration)
        guard originalDuration.seconds.isFinite, originalDuration.seconds > 0 else { throw VideoExportError.invalidMovie }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoExportError.writer }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: originalDuration), of: sourceTrack, at: .zero)
        if let sourceAudio = try await original.loadTracks(withMediaType: .audio).first,
           let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let range = try await sourceAudio.load(.timeRange)
            let usable = CMTimeRangeGetIntersection(range, otherRange: CMTimeRange(start: .zero, duration: originalDuration))
            try audio.insertTimeRange(usable, of: sourceAudio, at: usable.start)
        }
        var instruction = AVVideoCompositionInstruction.Configuration()
        instruction.timeRange = CMTimeRange(start: .zero, duration: originalDuration)
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        let transform = try await sourceTrack.load(.preferredTransform)
        let natural = try await sourceTrack.load(.naturalSize)
        let bounds = CGRect(origin: .zero, size: natural).applying(transform)
        guard bounds.width > 0, bounds.height > 0 else { throw VideoExportError.invalidMovie }
        let factor = min(quality.size.width / bounds.width, quality.size.height / bounds.height)
        let fitted = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(translationX: (quality.size.width - bounds.width * factor) / 2,
                                             y: (quality.size.height - bounds.height * factor) / 2))
        var layerInstruction = AVVideoCompositionLayerInstruction.Configuration(assetTrack: video)
        layerInstruction.setTransform(fitted, at: .zero)
        instruction.layerInstructions = [AVVideoCompositionLayerInstruction(configuration: layerInstruction)]
        let parent = CALayer(), videoLayer = CALayer(), captionLayer = CALayer()
        parent.frame = CGRect(origin: .zero, size: quality.size)
        videoLayer.frame = parent.bounds
        captionLayer.frame = parent.bounds
        captionLayer.contents = captionImage
        captionLayer.opacity = 0
        parent.addSublayer(videoLayer)
        parent.addSublayer(captionLayer)
        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.values = [1, 1, 0]
        visibility.keyTimes = [0, 0.9, 1]
        visibility.duration = 2
        visibility.beginTime = AVCoreAnimationBeginTimeAtZero
        visibility.isRemovedOnCompletion = false
        visibility.fillMode = .both
        captionLayer.add(visibility, forKey: "openingCaption")
        let animationTool = AVVideoCompositionCoreAnimationTool(configuration: .init(
            postProcessingAsVideoLayer: videoLayer, containingLayer: parent))
        let videoComposition = AVVideoComposition(configuration: .init(
            animationTool: animationTool,
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [AVVideoCompositionInstruction(configuration: instruction)],
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
    var showQuestionText = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export Take").font(.title2.bold())
            if showQuestionText { Text(question).lineLimit(4).foregroundStyle(.secondary) }
            Picker("Video quality", selection: $qualityValue) {
                ForEach(ExportQuality.allCases) { Text($0.label).tag($0.rawValue) }
            }.disabled(working)
            Text("Shows the question in a bottom caption for the first two seconds. Exports the full answer as an H.264 MP4.")
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
