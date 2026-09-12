import Foundation
import AVFoundation
import AppKit
import Testing
@testable import OuterView

@MainActor
struct VideoExportTests {
    @Test func titleCardExportProducesPlayableH264WithExpectedDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        let output = directory.appending(path: "export.mp4")
        try await TitleMovie.write(text: "Recorded answer", label: "Source", size: CGSize(width: 640, height: 480), to: source, seconds: 1)
        let audioURL = directory.appending(path: "tone.caf")
        let audioFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let samples = try #require(AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 44100))
        samples.frameLength = 44100
        let channel = try #require(samples.floatChannelData?[0])
        for index in 0..<44100 { channel[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44100)) * 0.1 }
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
            CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)), of: sourceVideo, at: .zero)
        try combined.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)), of: sourceAudio, at: .zero)
        let combinedURL = directory.appending(path: "with-audio.mov")
        let muxer = try #require(AVAssetExportSession(asset: combined, presetName: AVAssetExportPresetHighestQuality))
        try await muxer.export(to: combinedURL, as: .mov)
        let exporter = VideoExporter()
        try await exporter.export(source: combinedURL, question: "What is fairness? 공정함이란 무엇인가?", label: "Question 1.1", quality: .small, destination: output)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 4) < 0.15)
        let track = try #require(await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width == 960 && size.height == 540)
        let format = try #require(await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        let generator = AVAssetImageGenerator(asset: asset)
        let title = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        let answer = try await generator.image(at: CMTime(seconds: 3.5, preferredTimescale: 600)).image
        #expect(title.width == 960 && answer.width == 960)
        let audio = try #require(await asset.loadTracks(withMediaType: .audio).first)
        // MP4 export pads the audio track with silence, so inspect decoded samples
        // rather than assuming its track timeRange starts at the first sound.
        #expect(try amplitude(asset: asset, track: audio, start: 0.5) < 0.0001)
        #expect(try amplitude(asset: asset, track: audio, start: 3.25) > 0.03)
        Attachment.record(try #require(NSBitmapImageRep(cgImage: title).representation(using: .png, properties: [:])), named: "export-title.png")
        Attachment.record(try #require(NSBitmapImageRep(cgImage: answer).representation(using: .png, properties: [:])), named: "export-answer.png")
        Attachment.record(try Data(contentsOf: output), named: "export-smoke.mp4")
        #expect(exporter.progress == 1)
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

    @Test func cancelledTitleEncodingDoesNotComplete() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task {
            try await TitleMovie.write(text: "Cancel", label: "Question", size: CGSize(width: 960, height: 540), to: url)
        }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled encoding unexpectedly completed") }
        catch is CancellationError { }
    }
}
