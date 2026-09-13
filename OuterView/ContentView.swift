import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// Value drafts keep Cancel isolated from the saved SwiftData models.
nonisolated struct SetDraft: Identifiable, Sendable {
    var id = UUID()
    var title = "Untitled training set"
    var createdAt = Date()
    var lastOpenedAt: Date?
    var groups: [GroupDraft] = [GroupDraft()]

    static var sample: SetDraft {
        SetDraft(title: "Admissions practice · Sample", groups: [
            GroupDraft(label: "Ethics", questions: [QuestionDraft(text: "What does it mean to make a fair decision?"), QuestionDraft(text: "Describe a situation where two important values might conflict.")]),
            GroupDraft(label: "Personal experience", questions: [QuestionDraft(text: "Tell us about a time you changed your mind.")]),
            GroupDraft(label: "Looking ahead", questions: [QuestionDraft(text: "What would you like to contribute to your university community?")])
        ])
    }
}

nonisolated struct GroupDraft: Identifiable, Sendable {
    var id = UUID()
    var label = "New group"
    var imagePath: String?
    var imageData: Data?
    var questions = [QuestionDraft()]
}

nonisolated struct QuestionDraft: Identifiable, Sendable {
    var id = UUID()
    var text = ""
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var models: [TrainingSet]
    private var sets: [SetDraft] { models.map { SetDraft(model: $0) } }
    private var library: TrainingLibrary { TrainingLibrary(context: modelContext) }
    @State private var libraryError: String?
    @State private var deletion: SetDraft?
    @Environment(TrainingWindows.self) private var windows
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var draft: SetDraft?
    @State private var importOptions = false
    @State private var importingSet = false
    @State private var blindImport = false
    @State private var importSummary: String?
    @State private var exportingSet = false
    @State private var exportDocument: SharedSetDocument?
    @State private var exportName = "Training Set"
    @State private var sharingBusy = false

    var body: some View {
        launchScreen
        .frame(width: 820, height: 520)
        .disabled(sharingBusy)
        .overlay { if sharingBusy { ProgressView("Preparing training set…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .sheet(item: $draft) { value in
            SetEditor(initial: value) { saved in
                do {
                    try library.save(saved)
                    draft = nil
                    cleanupAssets()
                } catch { libraryError = error.localizedDescription }
            }
            .alert("Couldn’t Save Set", isPresented: Binding(get: { libraryError != nil }, set: { if !$0 { libraryError = nil } })) {
                Button("OK", role: .cancel) { libraryError = nil }
            } message: { Text(libraryError ?? "") }
        }
        .task {
            guard !windows.recovered else { return }
            windows.recovered = true
            do {
                let failures = await RecordingStore(context: modelContext, assets: try AssetStorage.applicationStorage()).recover()
                cleanupAssets()
                if !failures.isEmpty { libraryError = failures.joined(separator: "\n") }
            } catch { libraryError = error.localizedDescription }
        }
        .alert("Library Error", isPresented: Binding(get: { libraryError != nil && draft == nil }, set: { if !$0 { libraryError = nil } })) {
            Button("OK", role: .cancel) { libraryError = nil }
        } message: { Text(libraryError ?? "") }
        .confirmationDialog("Delete training set?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("Delete Set and Its Recordings", role: .destructive) {
                guard let value = deletion else { return }
                do { try library.delete(value.id); deletion = nil; cleanupAssets() }
                catch { libraryError = error.localizedDescription }
            }
        } message: { Text("This permanently removes \(deletion?.title ?? "this set"), its passages, questions, and recordings.") }
        .sheet(isPresented: $importOptions) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import a Shared Set").font(.title2.bold())
                Toggle("Blind import", isOn: $blindImport)
                Text(blindImport ? "Only group and question counts will be shown after import." : "Review passages and questions before saving the imported set.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { importOptions = false }
                    Spacer()
                    Button("Choose File…") { importOptions = false; importingSet = true }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 420)
        }
        .fileImporter(isPresented: $importingSet, allowedContentTypes: [.outerview, .zip]) { result in
            sharingBusy = true
            Task {
                defer { sharingBusy = false }
                do {
                    let url = try result.get()
                    let imported = try await Task.detached {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= StoredZIP.maximumSize else { throw ArchiveError.tooLarge }
                        return try TrainingArchive.decode(Data(contentsOf: url))
                    }.value
                    if blindImport {
                        try library.save(imported)
                        importSummary = "\(imported.groups.reduce(0) { $0 + $1.questions.count }) questions imported across \(imported.groups.count) groups."
                    } else { draft = imported }
                } catch { libraryError = error.localizedDescription }
            }
        }
        .fileExporter(isPresented: $exportingSet, document: exportDocument, contentType: .outerview, defaultFilename: exportName) { result in
            if case .failure(let error) = result { libraryError = error.localizedDescription }
            exportDocument = nil
        }
        .alert("Import Complete", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
            Button("OK", role: .cancel) { importSummary = nil }
        } message: { Text(importSummary ?? "") }
    }

    private func exportSet(_ set: SetDraft) {
        sharingBusy = true
        Task {
            defer { sharingBusy = false }
            do {
                let assets = try AssetStorage.applicationStorage()
                let data = try await Task.detached { try TrainingArchive.export(set, assets: assets) }.value
                exportDocument = SharedSetDocument(data: data)
                exportName = set.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                exportingSet = true
            } catch { libraryError = error.localizedDescription }
        }
    }

    private func cleanupAssets() {
        do { try library.cleanupAssets(AssetStorage.applicationStorage()) }
        catch { libraryError = "Your saved library is intact, but unused asset cleanup failed: " + error.localizedDescription }
    }

    private var recentSets: [SetDraft] {
        sets.sorted {
            if $0.lastOpenedAt != $1.lastOpenedAt {
                return ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func openSet(_ id: UUID) {
        guard !RecordingLifetime.shared.isLocked else { RecordingLifetime.shared.explain(); return }
        do {
            try library.markOpened(id)
            guard let model = try modelContext.fetch(FetchDescriptor<TrainingSet>()).first(where: { $0.id == id }) else { return }
            let set = SetDraft(model: model)
            Task {
                await RecordingLifetime.shared.capture?.shutdownAndWait()
                windows.sessionID = UUID()
                windows.set = set
                openWindow(id: "training")
                dismissWindow(id: "main")
            }
        }
        catch { libraryError = error.localizedDescription }
    }

    private static let launchIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) } ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    private var launchScreen: some View {
        HStack(spacing: 0) {
            VStack(spacing: 22) {
                Spacer(minLength: 10)
                Image(nsImage: Self.launchIcon)
                    .resizable().scaledToFit().frame(width: 100, height: 100)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("OuterView").font(.system(size: 32, weight: .bold))
                    Text("Interview practice, at your pace.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    welcomeAction("Create a Training Set…", icon: "plus") { draft = SetDraft() }
                    welcomeAction("Import a Shared Set…", icon: "square.and.arrow.down") { blindImport = false; importOptions = true }
                    welcomeAction("Explore a Sample", icon: "play") {
                        let sample = SetDraft.sample
                        do { try library.save(sample); openSet(sample.id) }
                        catch { libraryError = error.localizedDescription }
                    }
                }.padding(.top, 12)
                Spacer(minLength: 10)
            }
            .padding(30).frame(width: 350)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Recent Training Sets").font(.headline)
                    Spacer()
                    Image(systemName: "clock").foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.top, 24)
                if sets.isEmpty {
                    ContentUnavailableView("No recent training sets", systemImage: "rectangle.stack",
                        description: Text("Create a set or open one shared by a friend."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(recentSets) { set in
                                Button { openSet(set.id) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.richtext")
                                            .font(.system(size: 28)).foregroundStyle(.tint)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(set.title).font(.headline).lineLimit(2)
                                            Text("\(set.groups.count) groups · \(set.groups.reduce(0) { $0 + $1.questions.count }) questions")
                                                .font(.caption).foregroundStyle(.secondary)
                                            if let opened = set.lastOpenedAt {
                                                TimelineView(.periodic(from: .now, by: 60)) { _ in
                                                    Text(opened.formatted(.relative(presentation: .named, unitsStyle: .wide)))
                                                        .font(.caption2).foregroundStyle(.tertiary)
                                                        .help("Last opened " + opened.formatted(date: .complete, time: .shortened))
                                                }
                                            } else {
                                                Text("Not opened yet").font(.caption2).foregroundStyle(.tertiary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Edit…") { draft = set }.disabled(windows.set?.id == set.id)
                                        Button("Export Training Set…") { exportSet(set) }
                                        Button("Delete…", role: .destructive) { deletion = set }.disabled(windows.set?.id == set.id)
                                    }
                                Divider().padding(.leading, 52)
                            }
                        }.padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.2))
        }
        .background(.background)
    }

    private func welcomeAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

struct SetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SetDraft
    @State private var selected = 0
    @State private var pendingRemoval: (() -> Void)?
    @State private var pdfDocument: PDFDocument?
    @State private var cropping = false
    let save: (SetDraft) -> Void

    init(initial: SetDraft, save: @escaping (SetDraft) -> Void) {
        _draft = State(initialValue: initial)
        self.save = save
    }

    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.groups.allSatisfy { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.questions.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Prepare Training Set").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Set") { save(draft) }.buttonStyle(.borderedProminent)
                    .disabled(!valid).keyboardShortcut(.defaultAction)
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Set title", text: $draft.title).textFieldStyle(.roundedBorder)
                    Text("GROUPS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(draft.groups.indices, id: \.self) { index in
                                Button { selected = index } label: {
                                    HStack {
                                        Text("\(index + 1)").foregroundStyle(.secondary)
                                        Text(draft.groups[index].label).lineLimit(1)
                                        Spacer()
                                    }.padding(10)
                                        .background(selected == index ? Color.accentColor.opacity(0.12) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        Button("Move Group Up", systemImage: "arrow.up") {
                            draft.groups.swapAt(selected, selected - 1); selected -= 1
                        }.disabled(selected == 0)
                        Button("Move Group Down", systemImage: "arrow.down") {
                            draft.groups.swapAt(selected, selected + 1); selected += 1
                        }.disabled(selected == draft.groups.count - 1)
                        Button("Remove Group", systemImage: "trash", role: .destructive) {
                            pendingRemoval = {
                                draft.groups.remove(at: selected)
                                selected = min(selected, draft.groups.count - 1)
                            }
                        }.disabled(draft.groups.count == 1)
                    }.labelStyle(.iconOnly)
                    Button("Add Group", systemImage: "plus") {
                        draft.groups.append(GroupDraft())
                        selected = draft.groups.count - 1
                    }
                }.padding(20).frame(width: 240)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        TextField("Group label", text: $draft.groups[selected].label)
                            .font(.title2).textFieldStyle(.roundedBorder)
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Passage (optional)", systemImage: "doc.richtext").font(.headline)
                            if draft.groups[selected].imagePath != nil || draft.groups[selected].imageData != nil {
                                PassageImage(path: draft.groups[selected].imagePath, data: draft.groups[selected].imageData)
                                    .frame(maxHeight: 240)
                            } else {
                                Text("No passage. This group will start with its first question.")
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Crop from PDF…", systemImage: "crop") { cropping = true }
                                if draft.groups[selected].imagePath != nil || draft.groups[selected].imageData != nil {
                                    Button("Remove Passage", role: .destructive) {
                                        draft.groups[selected].imagePath = nil
                                        draft.groups[selected].imageData = nil
                                    }
                                }
                            }
                        }
                        Text("Questions").font(.headline)
                        ForEach(draft.groups[selected].questions.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Question \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Move Question Up", systemImage: "arrow.up") {
                                        draft.groups[selected].questions.swapAt(index, index - 1)
                                    }.disabled(index == 0)
                                    Button("Move Question Down", systemImage: "arrow.down") {
                                        draft.groups[selected].questions.swapAt(index, index + 1)
                                    }.disabled(index == draft.groups[selected].questions.count - 1)
                                    Button("Remove Question", systemImage: "trash", role: .destructive) {
                                        pendingRemoval = { draft.groups[selected].questions.remove(at: index) }
                                    }.disabled(draft.groups[selected].questions.count == 1)
                                }.labelStyle(.iconOnly)
                                TextEditor(text: $draft.groups[selected].questions[index].text)
                                    .font(.body).frame(height: 72).padding(8)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            }
                        }
                        Button("Add Question", systemImage: "plus") {
                            draft.groups[selected].questions.append(QuestionDraft())
                        }
                    }.padding(24)
                }.id(draft.groups[selected].id)
            }
        }.frame(width: 900, height: 620)
        .sheet(isPresented: $cropping) {
            PDFCropSheet(document: $pdfDocument) { data in
                draft.groups[selected].imageData = data
            }
        }
        .confirmationDialog("Remove this content?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { pendingRemoval?(); pendingRemoval = nil }
        } message: {
            Text("Saving the set will also delete recordings belonging to the removed questions. Cancel the editor to keep the original set.")
        }
    }
}


#Preview {
    ContentView().environment(TrainingWindows()).modelContainer(for: [TrainingSet.self, PassageGroup.self, Question.self, Take.self], inMemory: true)
}
