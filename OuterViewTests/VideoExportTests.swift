import Foundation
import AVFoundation
import AppKit
import CoreText
import Testing
@testable import OuterView

@MainActor
struct VideoExportTests {
    @Test func captionExportPreservesTimingAndClearsAfterTwoSeconds() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        let output = directory.appending(path: "export.mp4")
        try await TitleMovie.write(text: "Recorded answer", label: "Source", size: CGSize(width: 640, height: 480), to: source, seconds: 3)
        let thumbnail = try await TakeThumbnail.frame(from: source)
        #expect(thumbnail.width <= 416 && thumbnail.height <= 234)
        #expect(abs(Double(thumbnail.width) / Double(thumbnail.height) - 4.0 / 3.0) < 0.02)
        Attachment.record(try #require(NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:])), named: "take-thumbnail.png")
        let audioURL = directory.appending(path: "tone.caf")
        let audioFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let samples = try #require(AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 132300))
        samples.frameLength = 132300
        let channel = try #require(samples.floatChannelData?[0])
        for index in 0..<132300 { channel[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44100)) * 0.1 }
        do {
            let audioFile = try AVAudioFile(forWriting: audioURL, settings: audioFormat.settings)
            try audioFile.write(from: samples)
        }
        let combined = AVMutableComposition()
        let sourceAsset = AVURLAsset(url: source)
        let audioAsset = AVURLAsset(url: audioURL)
        let sourceVideo = try #require(await sourceAsset.loadTracks(withMediaType: .video).first)
        let sourceAudio = try #require(await audioAsset.loadTracks(withMediaType: .audio).first)
        try combined.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)), of: sourceVideo, at: .zero)
        try combined.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)), of: sourceAudio, at: .zero)
        let combinedURL = directory.appending(path: "with-audio.mov")
        let muxer = try #require(AVAssetExportSession(asset: combined, presetName: AVAssetExportPresetHighestQuality))
        try await muxer.export(to: combinedURL, as: .mov)
        let exporter = VideoExporter()
        try await exporter.export(source: combinedURL, question: "What is fairness? 공정함이란 무엇인가?", label: "Question 1.1", quality: .small, destination: output)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 3) < 0.15)
        let track = try #require(await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width == 960 && size.height == 540)
        let format = try #require(await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        let generator = AVAssetImageGenerator(asset: asset)
        let title = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        let answer = try await generator.image(at: CMTime(seconds: 2.5, preferredTimescale: 600)).image
        #expect(title.width == 960 && answer.width == 960)
        let audio = try #require(await asset.loadTracks(withMediaType: .audio).first)
        // Audio begins immediately and remains aligned after the caption disappears.
        #expect(try amplitude(asset: asset, track: audio, start: 0.1) > 0.03)
        #expect(try amplitude(asset: asset, track: audio, start: 2.25) > 0.03)
        #expect(try frameDifference(title, answer, region: CGRect(x: 0, y: 0, width: 960, height: 270)) < 3)
        #expect(try frameDifference(title, answer, region: CGRect(x: 0, y: 370, width: 960, height: 170)) > 15)
        Attachment.record(try #require(NSBitmapImageRep(cgImage: title).representation(using: .png, properties: [:])), named: "export-caption.png")
        Attachment.record(try #require(NSBitmapImageRep(cgImage: answer).representation(using: .png, properties: [:])), named: "export-answer.png")
        Attachment.record(try Data(contentsOf: output), named: "export-smoke.mp4")
        #expect(exporter.progress == 1)
    }
    private func frameDifference(_ first: CGImage, _ second: CGImage, region: CGRect) throws -> Double {
        func pixels(_ image: CGImage) throws -> [UInt8] {
            let crop = try #require(image.cropping(to: region))
            var data = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            try data.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                    bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            }
            return data
        }
        let a = try pixels(first), b = try pixels(second)
        return zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
    }

    private func amplitude(asset: AVAsset, track: AVAssetTrack, start: Double) throws -> Double {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 44100), duration: CMTime(seconds: 0.5, preferredTimescale: 44100))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        #expect(reader.startReading())
        var sum = 0.0, count = 0
        while let sample = output.copyNextSampleBuffer() {
            let block = try #require(CMSampleBufferGetDataBuffer(sample))
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = values.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            #expect(status == kCMBlockBufferNoErr)
            sum += values.reduce(0) { $0 + abs(Double($1)) }
            count += values.count
        }
        #expect(reader.status == .completed)
        return count > 0 ? sum / Double(count) : 0
    }

    @Test func cancelledCaptionExportDoesNotCreateOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        let output = directory.appending(path: "cancelled.mp4")
        try await TitleMovie.write(text: "Answer", label: "Source", size: CGSize(width: 640, height: 480), to: source, seconds: 0.5)
        let exporter = VideoExporter()
        let task = Task {
            try await exporter.export(source: source, question: "Cancelled question", label: "Question 1.1",
                quality: .small, destination: output)
        }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled export unexpectedly completed") }
        catch is CancellationError { }
        #expect(!FileManager.default.fileExists(atPath: output.path))
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
