import SwiftUI
import SwiftData
import AVKit

struct PracticeWorkspace: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTakes: [Take]
    @StateObject private var capture = CaptureController()
    @State private var journal: RecordingJournal?
    @State private var saveError: String?
    @State private var playing: Take?
    @State private var exportingTake: Take?
    @State private var deviceSettings = false
    private var locked: Bool { progress.isLocked || capture.locked }
    private var activeTakes: [Take] {
        guard let index = questionIndex else { return [] }
        return allTakes.filter { $0.question?.id == group.questions[index].id }.sorted { $0.recordedAt > $1.recordedAt }
    }
    let set: SetDraft
    let goHome: () -> Void
    let edit: () -> Void
    @State private var progress = SessionProgress()
    private var groupIndex: Int { progress.groupIndex }
    private var questionIndex: Int? { progress.questionIndex }
    @AppStorage("showPassage") private var showPassage = true
    @AppStorage("showQuestion") private var showQuestion = true
    @State private var showCamera = true
    @State private var showTimer = true
    @State private var showTakes = true

    private var group: GroupDraft { self.set.groups[groupIndex] }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(set.title).font(.headline).padding(.horizontal)
                Text("PASSAGE GROUPS").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).padding(.horizontal)
                List(selection: Binding(get: { groupIndex }, set: { progress.selectGroup($0, count: set.groups.count) })) {
                    ForEach(set.groups.indices, id: \.self) { index in
                        Label(set.groups[index].label, systemImage: "rectangle.stack").tag(index)
                    }
                }.disabled(locked)
                Button("Edit Training Set", systemImage: "pencil", action: edit).disabled(locked).padding()
            }.padding(.top, 20)
                .frame(width: 220)
                .frame(maxHeight: .infinity)
                .background(.quaternary.opacity(0.2))
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Text(group.label).font(.title2.bold())
                            Spacer()
                        }
                        if let index = questionIndex {
                            Text("QUESTION \(index + 1) OF \(group.questions.count)")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if showQuestion {
                                ScrollView {
                                    Text(group.questions[index].text).font(.system(size: 28, weight: .medium))
                                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                }
                            } else {
                                Label("Question hidden", systemImage: "eye.slash").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let path = group.imagePath, showPassage {
                                ScrollView { PassageImage(path: path) }.frame(maxHeight: 240)
                            }
                        } else if progress.stage == .reading {
                            Text("READING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if showPassage {
                                ScrollView { PassageImage(path: group.imagePath) }
                            } else {
                                ContentUnavailableView("Passage hidden", systemImage: "eye.slash",
                                    description: Text("Passage visibility can be changed in Settings. Press Next when ready."))
                            }
                        } else {
                            ContentUnavailableView("Ready when you are", systemImage: "rectangle.stack",
                                description: Text(group.imagePath == nil ? "Start this group to reveal its first question. Take your time before recording." : "Start this group to reveal its passage. Press Next when you’re ready for the questions."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Divider()
                    VStack(spacing: 20) {
                        RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.4))
                            .frame(width: 212, height: 282)
                            .overlay {
                                if showCamera && capture.state != .idle && capture.state != .preparing {
                                    CameraPreview(session: capture.engine.session).clipShape(RoundedRectangle(cornerRadius: 16))
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: showCamera ? "video" : "video.slash").font(.largeTitle)
                                        Text(showCamera ? "Camera not enabled" : "Camera hidden").font(.headline)
                                        if showCamera { Text("Use Enable Camera in the toolbar").font(.caption) }
                                    }.foregroundStyle(.secondary)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                visibilityButton("Camera", visible: $showCamera).padding(10)
                            }
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            VStack(spacing: 10) {
                                Text(showTimer ? SessionProgress.clock(progress.elapsed(at: timeline.date)) : "—:—")
                                    .font(.system(size: 36, weight: .light, design: .monospaced))
                                Text(showTimer ? (progress.stage == .reading ? "Reading elapsed" : "Recording elapsed") : "Timer hidden")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 42).padding(.bottom, 20)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topTrailing) {
                            visibilityButton("Timer", visible: $showTimer).padding(10)
                        }
                        Spacer()
                    }.padding(24).frame(width: 260)
                }
                Divider()
                DisclosureGroup(isExpanded: $showTakes) {
                    if let saveError {
                        HStack {
                            Text(saveError).foregroundStyle(.red).font(.caption)
                            Button("Retry Save") { saveCompletedTake() }
                        }.padding(.vertical, 8)
                    }
                    if activeTakes.isEmpty {
                        Text(questionIndex == nil ? "Reveal a question to review its takes." : "No takes yet. Record an answer when you’re ready.")
                            .foregroundStyle(.secondary).padding(.vertical, 20)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(activeTakes) { take in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(take.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                        Text(SessionProgress.clock(take.durationSeconds)).monospacedDigit()
                                        HStack {
                                            Button("Play", systemImage: "play.fill") { playing = take }
                                            Button("Export", systemImage: "square.and.arrow.up") { exportingTake = take }
                                            Button("Retry", systemImage: "arrow.counterclockwise") { startRecording() }
                                                .disabled(capture.state != .ready)
                                        }.disabled(locked)
                                    }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }.frame(height: 115)
                    }
                } label: {
                    Text("Takes\(questionIndex.map { " · Question \($0 + 1)" } ?? "")").font(.headline)
                }.padding(20)
            }
            .background(.background)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Training Sets", systemImage: "chevron.left", action: goHome).disabled(locked)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Devices", systemImage: "video.badge.ellipsis") { capture.refreshDevices(); deviceSettings = true }
                    .disabled(locked || capture.state == .preparing)
                    .popover(isPresented: $deviceSettings) {
                        Form {
                            Picker("Camera", selection: $capture.cameraID) {
                                ForEach(capture.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                            }
                            Picker("Microphone", selection: $capture.microphoneID) {
                                ForEach(capture.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                            }
                            Button("Apply Devices") { deviceSettings = false; Task { await capture.enable() } }
                        }.padding(20).frame(width: 360)
                    }
                if capture.state == .idle {
                    Button("Enable Camera", systemImage: "video") { Task { await capture.enable() } }
                } else if capture.state == .preparing {
                    ProgressView().controlSize(.small)
                }
                if let index = questionIndex {
                    Button("Previous", systemImage: "chevron.left") { progress.previous(hasPassage: group.imagePath != nil) }
                        .disabled(locked || (index == 0 && group.imagePath == nil))
                    Button(index == group.questions.count - 1 ? "Finish Group" : "Next", systemImage: "chevron.right") {
                        progress.next(questionCount: group.questions.count)
                    }.disabled(locked)
                    if capture.state == .recording || capture.state == .starting {
                        Button("Stop", systemImage: "stop.fill") { progress.beginSaving(); capture.stop() }
                            .tint(.red)
                    } else if capture.state == .saving {
                        ProgressView("Saving…").controlSize(.small)
                    } else {
                        Button("Record", systemImage: "record.circle") { startRecording() }
                            .disabled(capture.state != .ready || locked)
                    }
                } else if progress.stage == .reading {
                    Button("Next", systemImage: "chevron.right") { progress.next(questionCount: group.questions.count) }
                } else {
                    Button("Start", systemImage: "play.fill") { progress.start(hasPassage: group.imagePath != nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(RecordingCloseGuard(locked: locked).frame(width: 0, height: 0))
        .onReceive(capture.$completed) { movie in
            if movie != nil { DispatchQueue.main.async { saveCompletedTake() } }
        }
        .onChange(of: capture.state) { _, state in
            if state == .saving { progress.beginSaving() }
            if (state == .ready || state == .idle) && capture.completed == nil && progress.isLocked { progress.finishSaving() }
        }
        .onDisappear { capture.shutdown(); RecordingLifetime.shared.locked = false }
        .sheet(item: $playing) { TakePlayer(take: $0) }
        .sheet(item: $exportingTake) { take in
            if let index = questionIndex {
                VideoExportSheet(take: take, question: group.questions[index].text,
                    groupNumber: groupIndex + 1, questionNumber: index + 1,
                    takeNumber: (Array(activeTakes.reversed()).firstIndex(where: { $0.id == take.id }) ?? 0) + 1,
                    setTitle: set.title)
            }
        }
        .alert("Recording Error", isPresented: Binding(get: { capture.error != nil }, set: { if !$0 { capture.error = nil } })) {
            Button("OK", role: .cancel) { capture.error = nil }
        } message: { Text(capture.error ?? "") }
    }

    private func startRecording() {
        guard capture.state == .ready, !locked, let index = questionIndex else { return }
        do {
            let store = RecordingStore(context: modelContext, assets: try AssetStorage.applicationStorage())
            let pending = try store.prepare(setID: set.id, questionID: group.questions[index].id)
            journal = pending
            saveError = nil
            progress.beginRecording()
            RecordingLifetime.shared.locked = true
            capture.record(to: store.movieURL(pending.id))
        } catch { capture.error = error.localizedDescription }
    }

    private func saveCompletedTake() {
        guard let movie = capture.completed, let journal else { return }
        do {
            try RecordingStore(context: modelContext, assets: AssetStorage.applicationStorage()).save(journal, duration: movie.duration)
            saveError = nil
            self.journal = nil
            capture.didSave()
            progress.finishSaving()
        } catch { saveError = "Recording retained, but saving failed: " + error.localizedDescription }
    }

    private func visibilityButton(_ name: String, visible: Binding<Bool>) -> some View {
        Button { visible.wrappedValue.toggle() } label: {
            Label("\(visible.wrappedValue ? "Hide" : "Show") \(name.lowercased())", systemImage: visible.wrappedValue ? "eye" : "eye.slash")
                .labelStyle(.iconOnly)
        }
        .help("\(visible.wrappedValue ? "Hide" : "Show") \(name.lowercased())")
        .accessibilityValue(visible.wrappedValue ? "Visible" : "Hidden")
    }
}


struct TakePlayer: View {
    @Environment(\.dismiss) private var dismiss
    let take: Take
    @State private var player: AVPlayer?
    @State private var error: String?
    var body: some View {
        VStack {
            HStack {
                Text(take.recordedAt.formatted()).font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let player { VideoPlayer(player: player) }
            else { ContentUnavailableView(error ?? "Loading recording…", systemImage: "film") }
        }.padding(20).frame(width: 800, height: 550)
        .task {
            do {
                let url = try AssetStorage.applicationStorage().url(for: take.videoPath)
                guard FileManager.default.fileExists(atPath: url.path) else { throw RecordingStoreError.invalidMovie }
                player = AVPlayer(url: url)
                player?.play()
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { player?.pause() }
    }
}
