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
    @AppStorage("showTakes") private var showTakes = true
    @AppStorage("takesPanelHeight") private var takesPanelHeight = 242.0
    @State private var resizeStart: Double?

    private var group: GroupDraft { self.set.groups[groupIndex] }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(set.title).font(.headline).padding(.horizontal)
                Text("PASSAGE GROUPS").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).padding(.horizontal)
                List(selection: Binding(get: { groupIndex }, set: { endTraining(); progress.selectGroup($0, count: set.groups.count) })) {
                    ForEach(set.groups.indices, id: \.self) { index in
                        Label(set.groups[index].label, systemImage: "rectangle.stack").tag(index)
                    }
                }.disabled(locked)
                Button("Edit Training Set", systemImage: "pencil") { endTraining(); edit() }.disabled(locked).padding()
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
                            .frame(width: 252, height: 142)
                            .overlay {
                                if showCamera && capture.state != .idle && capture.state != .preparing {
                                    CameraPreview(session: capture.engine.session).clipShape(RoundedRectangle(cornerRadius: 16))
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: showCamera ? "video" : "video.slash").font(.largeTitle)
                                        Text(showCamera ? (capture.state == .preparing ? "Starting camera…" : (progress.isTraining ? "Camera unavailable" : "Camera off")) : "Camera hidden").font(.headline)
                                        if showCamera { Text(capture.state == .preparing ? "Preparing your devices" : (progress.isTraining ? "Use Retry Camera in the toolbar" : "Press Start to begin training")).font(.caption) }
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
                    }.padding(24).frame(width: 300)
                }
                takesPanel

            }
            .background(.background)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Training Sets", systemImage: "chevron.left") { endTraining(); goHome() }.disabled(locked)
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
                            Button("Apply Devices") { deviceSettings = false; capture.retryCamera() }
                        }.padding(20).frame(width: 360)
                    }
                if progress.isTraining && capture.state == .idle {
                    Button("Retry Camera", systemImage: "video") { capture.retryCamera() }
                } else if capture.state == .preparing {
                    ProgressView().controlSize(.small)
                }
                if progress.isTraining {
                    Button("End Training", systemImage: "xmark.circle") { endTraining() }
                        .disabled(locked)
                }
                if let index = questionIndex {
                    Button("Previous", systemImage: "chevron.left") { progress.previous(hasPassage: group.imagePath != nil) }
                        .disabled(locked || (index == 0 && group.imagePath == nil))
                    Button(index == group.questions.count - 1 ? "Finish Group" : "Next", systemImage: "chevron.right") {
                        progress.next(questionCount: group.questions.count)
                        if !progress.isTraining { capture.shutdown() }
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
                    Button("Start", systemImage: "play.fill") {
                        progress.start(hasPassage: group.imagePath != nil)
                        capture.startTraining()
                    }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(RecordingCloseGuard(capture: capture, locked: locked).frame(width: 0, height: 0))
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

    private var takesPanel: some View {
        VStack(spacing: 0) {
            if showTakes {
                Rectangle().fill(.quaternary).frame(height: 5)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if resizeStart == nil { resizeStart = takesPanelHeight }
                            takesPanelHeight = min(300, max(242, (resizeStart ?? 242) - value.translation.height))
                        }
                        .onEnded { _ in resizeStart = nil })
                    .accessibilityLabel("Resize takes panel")
                    .accessibilityAdjustableAction { direction in
                        takesPanelHeight = min(300, max(242, takesPanelHeight + (direction == .increment ? 20 : -20)))
                    }
            } else { Divider() }
            HStack(spacing: 8) {
                Button { showTakes.toggle() } label: {
                    Label(showTakes ? "Hide takes" : "Show takes", systemImage: "rectangle.bottomthird.inset.filled")
                        .labelStyle(.iconOnly)
                }.buttonStyle(.plain).help(showTakes ? "Hide takes" : "Show takes")
                Text("Takes").font(.headline)
                if let questionIndex {
                    Text("Question \(questionIndex + 1) · \(activeTakes.count) takes").foregroundStyle(.secondary)
                }
                Spacer()
                Button { showTakes.toggle() } label: {
                    Image(systemName: showTakes ? "chevron.down" : "chevron.up")
                }.buttonStyle(.plain).accessibilityLabel(showTakes ? "Collapse takes" : "Expand takes")
            }.padding(.horizontal, 16).frame(height: 36)
            if showTakes {
                Divider()
                if let saveError {
                    HStack {
                        Text(saveError).foregroundStyle(.red).font(.caption).lineLimit(2)
                        Button("Retry Save") { saveCompletedTake() }
                    }.padding(8)
                }
                if activeTakes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack").font(.title2)
                        Text(questionIndex == nil ? "Reveal a question to review its takes." : "No takes yet. Record an answer when you’re ready.")
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(activeTakes) { take in
                                VStack(alignment: .leading, spacing: 8) {
                                    Button { playing = take } label: {
                                        TakeThumbnail(path: take.videoPath)
                                            .frame(width: 208, height: 117)
                                            .overlay(alignment: .bottomTrailing) {
                                                Text(SessionProgress.clock(take.durationSeconds))
                                                    .font(.caption.monospacedDigit()).padding(4)
                                                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                                    .foregroundStyle(.white).padding(6)
                                            }
                                    }.buttonStyle(.plain).disabled(locked).accessibilityLabel("Play recording")
                                    Text(take.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                    HStack {
                                        Button("Play", systemImage: "play.fill") { playing = take }
                                        Button("Export", systemImage: "square.and.arrow.up") { exportingTake = take }
                                        Button("Retry", systemImage: "arrow.counterclockwise") { startRecording() }
                                            .disabled(capture.state != .ready)
                                    }.controlSize(.small).disabled(locked)
                                }.frame(width: 208)
                            }
                        }.padding(12)
                    }.frame(maxHeight: .infinity)
                }
            }
        }
        .frame(height: showTakes ? min(300, max(242, takesPanelHeight)) : 37)
        .background(.quaternary.opacity(0.12))
    }

    private func endTraining() {
        guard !locked else { return }
        progress.endTraining()
        capture.shutdown()
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

struct TakeThumbnail: View {
    let path: String
    @State private var thumbnail: NSImage?
    @State private var unavailable = false
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        return cache
    }()

    var body: some View {
        ZStack {
            Color.black
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else if unavailable {
                Image(systemName: "film").font(.title).foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: path) {
            thumbnail = nil
            unavailable = false
            if let cached = Self.cache.object(forKey: path as NSString) { thumbnail = cached; return }
            do {
                let url = try AssetStorage.applicationStorage().url(for: path)
                let frame = try await Self.frame(from: url)
                try Task.checkCancellation()
                let image = NSImage(cgImage: frame, size: .zero)
                Self.cache.setObject(image, forKey: path as NSString)
                thumbnail = image
            } catch { if !Task.isCancelled { unavailable = true } }
        }
    }

    static func frame(from url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 416, height: 234)
        return try await generator.image(at: .zero).image
    }

}
