import AVFoundation
import Foundation
import Testing
@testable import OuterView

private actor CaptureGate {
    private var entered = false
    private var released = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        arrivals.forEach { $0.resume() }; arrivals.removeAll()
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { arrivals.append($0) } }
    }
    func release() {
        released = true
        waiters.forEach { $0.resume() }; waiters.removeAll()
    }
}

private nonisolated final class TestCaptureEngine: CaptureSessionEngine, @unchecked Sendable {
    let session = AVCaptureSession()
    var finished: (@Sendable (URL, String?) -> Void)?
    var started: (@Sendable () -> Void)?
    var interrupted: (@Sendable (String) -> Void)?
    let gate: CaptureGate?
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var running = false
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    var isRunning: Bool { lock.withLock { running } }
    init(gate: CaptureGate? = nil) { self.gate = gate }
    func configure(camera: String, microphone: String, activation: CaptureActivation) async throws {
        await gate?.wait()
        guard !activation.isCancelled else { throw CancellationError() }
        lock.withLock { starts += 1; running = true }
    }
    func record(to url: URL) { started?() }
    func stopRecording() { }
    func shutdown() async { lock.withLock { stops += 1; running = false } }
}

@MainActor
struct CaptureLifecycleTests {
    @Test func deckDeviceChangesCannotStartCapture() async {
        let engine = TestCaptureEngine()
        let controller = CaptureController(engine: engine, requestPermission: { _ in
            Issue.record("Permissions were requested before Start")
            return false
        })
        controller.cameraID = "selected camera"
        controller.microphoneID = "selected microphone"
        #expect(controller.retryCamera() == nil)
        #expect(!controller.trainingActive && controller.state == .idle)
        #expect(engine.startCount == 0)
    }

    @Test func startAndEndTrainingOwnDeviceLifetime() async {
        let engine = TestCaptureEngine()
        let controller = CaptureController(engine: engine, requestPermission: { _ in true })
        await controller.startTraining()?.value
        #expect(controller.trainingActive && controller.state == .ready)
        #expect(engine.isRunning && engine.startCount == 1)
        #expect(controller.startTraining() == nil)
        await controller.shutdownAndWait()
        #expect(!controller.trainingActive && controller.state == .idle)
        #expect(!engine.isRunning && engine.stopCount == 1)
    }

    @Test func viewRemovalDefersPublishedStateUntilAfterReconciliation() async {
        let engine = TestCaptureEngine()
        let controller = CaptureController(engine: engine, requestPermission: { _ in true })
        await controller.startTraining()?.value
        let shutdown = controller.shutdownAfterViewRemoval()
        #expect(controller.trainingActive && controller.state == .ready)
        await shutdown.value
        #expect(!controller.trainingActive && controller.state == .idle)
        #expect(!engine.isRunning)
    }

    @Test func endingDuringPermissionRequestCannotReactivateCamera() async {
        let permissions = CaptureGate()
        let engine = TestCaptureEngine()
        let controller = CaptureController(engine: engine, requestPermission: { _ in await permissions.wait(); return true })
        let setup = controller.startTraining()
        await permissions.waitUntilEntered()
        await controller.shutdownAndWait()
        await permissions.release()
        await setup?.value
        #expect(controller.state == .idle && !controller.trainingActive)
        #expect(!engine.isRunning && engine.startCount == 0)
    }

    @Test func cancelledSetupCannotStopANewerTrainingSession() async {
        let configuration = CaptureGate()
        let engine = TestCaptureEngine(gate: configuration)
        let controller = CaptureController(engine: engine, requestPermission: { _ in true })
        let first = controller.startTraining()
        await configuration.waitUntilEntered()
        await controller.shutdownAndWait()
        let second = controller.startTraining()
        await configuration.release()
        await first?.value
        await second?.value
        #expect(engine.startCount == 1 && engine.stopCount == 1 && engine.isRunning)
        #expect(controller.trainingActive && controller.state == .ready)
        await controller.shutdownAndWait()
    }

    @Test func nativeEngineHonorsCancelledActivationWithoutOpeningDevices() async {
        let engine = CaptureEngine()
        let request = CaptureActivation()
        request.cancel()
        do {
            try await engine.configure(camera: "unused", microphone: "unused", activation: request)
            Issue.record("Cancelled activation unexpectedly succeeded")
        } catch is CancellationError { }
        catch { Issue.record(error) }
        await engine.shutdown()
        #expect(!engine.session.isRunning)
    }

    @Test func endTrainingReturnsToDeckButCannotDiscardActiveRecording() {
        var session = SessionProgress()
        session.start(hasPassage: true)
        session.endTraining()
        #expect(!session.isTraining && session.questionIndex == nil)
        session.start(hasPassage: false)
        session.beginRecording()
        session.endTraining()
        #expect(session.stage == .recording)
        session.beginSaving()
        session.endTraining()
        #expect(session.stage == .saving)
        session.finishSaving()
        session.endTraining()
        #expect(session.stage == .deck)
    }
}
