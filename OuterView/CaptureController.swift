import AVFoundation
import SwiftUI
import Combine

struct RecordedMovie: Identifiable {
    let id = UUID()
    let url: URL
    let duration: Double
}

enum CaptureFailure: LocalizedError {
    case permission, device, busy
    var errorDescription: String? {
        switch self {
        case .permission: "Camera and microphone access are required. Enable them for OuterView in System Settings → Privacy & Security, then try again."
        case .device: "The selected camera or microphone is unavailable. Connect a device and choose it again."
        case .busy: "The camera is not ready yet."
        }
    }
}

/// AVCaptureSession is configured and started exclusively on this queue.
nonisolated final class CaptureEngine: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.jongwoo.OuterView.capture")
    private let output = AVCaptureMovieFileOutput()
    var finished: (@Sendable (URL, String?) -> Void)?
    var started: (@Sendable () -> Void)?
    var interrupted: (@Sendable (String) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "The capture device stopped unexpectedly."
            self?.interrupted?(message)
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                if self.session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).contains(where: { !$0.device.isConnected }) {
                    if self.output.isRecording { self.output.stopRecording() }
                    self.interrupted?("A recording device disconnected. Reconnect it and enable the camera again.")
                }
            }
        })
    }

    func configure(camera: String, microphone: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard !self.output.isRecording else { throw CaptureFailure.busy }
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.inputs.forEach { self.session.removeInput($0) }
                    guard let video = AVCaptureDevice(uniqueID: camera), let audio = AVCaptureDevice(uniqueID: microphone) else { throw CaptureFailure.device }
                    for device in [video, audio] {
                        let input = try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input) else { throw CaptureFailure.device }
                        self.session.addInput(input)
                    }
                    if self.session.canSetSessionPreset(.high) { self.session.sessionPreset = .high }
                    if !self.session.outputs.contains(self.output) {
                        guard self.session.canAddOutput(self.output) else { throw CaptureFailure.device }
                        self.session.addOutput(self.output)
                    }
                    // Source movies remain unmirrored; only the live preview is mirrored.
                    if let connection = self.output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        await withCheckedContinuation { continuation in
            queue.async { self.session.startRunning(); continuation.resume() }
        }
    }

    func record(to url: URL) { queue.async { self.output.startRecording(to: url, recordingDelegate: self) } }
    func stopRecording() { queue.async { if self.output.isRecording { self.output.stopRecording() } } }
    func shutdown() { queue.async { if !self.output.isRecording { self.session.stopRunning() } } }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) { started?() }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let successful = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        finished?(fileURL, successful ? nil : error?.localizedDescription ?? "The recording could not be saved.")
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

@MainActor
final class CaptureController: ObservableObject {
    enum State { case idle, preparing, ready, starting, recording, saving }
    let engine = CaptureEngine()
    private var enableGeneration = UUID()
    @Published var state: State = .idle
    @Published var error: String?
    @Published var completed: RecordedMovie?
    @Published var cameraID = ""
    @Published var microphoneID = ""
    @Published var cameras: [AVCaptureDevice] = []
    @Published var microphones: [AVCaptureDevice] = []
    var locked: Bool { state == .starting || state == .recording || state == .saving }

    init() {
        refreshDevices()
        engine.started = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state == .saving { self.engine.stopRecording() }
                else { self.state = .recording }
            }
        }
        engine.finished = { [weak self] url, failure in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let failure { self.error = failure; self.state = .idle; return }
                do {
                    let duration = try await AVURLAsset(url: url).load(.duration).seconds
                    guard duration.isFinite && duration > 0 else { throw CaptureFailure.busy }
                    self.completed = RecordedMovie(url: url, duration: duration)
                    // Remain in saving until the database confirms this take.
                    self.state = .saving
                } catch { self.error = error.localizedDescription; self.state = .idle }
            }
        }
        engine.interrupted = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.error = message
                if self.locked { self.stop() } else { self.state = .idle }
            }
        }
    }
    func refreshDevices() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
        microphones = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        if !cameras.contains(where: { $0.uniqueID == cameraID }) { cameraID = AVCaptureDevice.default(for: .video)?.uniqueID ?? cameras.first?.uniqueID ?? "" }
        if !microphones.contains(where: { $0.uniqueID == microphoneID }) { microphoneID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? microphones.first?.uniqueID ?? "" }
    }
    func enable() async {
        guard !locked else { return }
        state = .preparing
        let generation = UUID()
        enableGeneration = generation
        do {
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw CaptureFailure.permission }
            guard enableGeneration == generation else { return }
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw CaptureFailure.permission }
            guard enableGeneration == generation else { return }
            refreshDevices()
            try await engine.configure(camera: cameraID, microphone: microphoneID)
            guard enableGeneration == generation else { engine.shutdown(); return }
            state = .ready
        } catch {
            guard enableGeneration == generation else { return }
            self.error = error.localizedDescription; state = .idle
        }
    }
    func shutdown() {
        enableGeneration = UUID()
        engine.shutdown()
        if !locked { state = .idle }
    }
    func record(to url: URL) {
        guard state == .ready else { return }
        state = .starting
        completed = nil
        engine.record(to: url)
    }
    func stop() {
        guard state == .recording || state == .starting else { return }
        state = .saving
        engine.stopRecording()
    }
    func didSave() { completed = nil; state = .ready }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateNSView(_ nsView: PreviewSurface, context: Context) {
        if let connection = nsView.preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
    final class PreviewSurface: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer = preview }
        required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; layer = preview }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
