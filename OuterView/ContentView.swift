import SwiftUI
import SwiftData

// Value drafts keep Cancel isolated from the saved SwiftData models.
struct SetDraft: Identifiable {
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

struct GroupDraft: Identifiable {
    var id = UUID()
    var label = "New group"
    var imagePath: String?
    var questions = [QuestionDraft()]
}

struct QuestionDraft: Identifiable {
    var id = UUID()
    var text = ""
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var models: [TrainingSet]
    private var sets: [SetDraft] { models.map(SetDraft.init(model:)) }
    private var library: TrainingLibrary { TrainingLibrary(context: modelContext) }
    @State private var libraryError: String?
    @State private var deletion: SetDraft?
    @State private var activeID: UUID?
    @State private var workspaceRevision = 0
    @State private var draft: SetDraft?
    @State private var notice = false

    var body: some View {
        GeometryReader { geometry in
            Group {
            if let index = sets.firstIndex(where: { $0.id == activeID }) {
                PracticeWorkspace(set: sets[index], goHome: { activeID = nil }, edit: { draft = sets[index] })
                    .id("\(sets[index].id)-\(workspaceRevision)")
            } else {
                launchScreen
            }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: activeID == nil ? 820 : 1000,
               idealWidth: activeID == nil ? 820 : 1180,
               maxWidth: activeID == nil ? 820 : .infinity,
               minHeight: activeID == nil ? 520 : 680,
               idealHeight: activeID == nil ? 520 : 780,
               maxHeight: activeID == nil ? 520 : .infinity)
        .sheet(item: $draft) { value in
            SetEditor(initial: value) { saved in
                do {
                    try library.save(saved)
                    workspaceRevision += 1
                    draft = nil
                    cleanupAssets()
                } catch { libraryError = error.localizedDescription }
            }
            .alert("Couldn’t Save Set", isPresented: Binding(get: { libraryError != nil }, set: { if !$0 { libraryError = nil } })) {
                Button("OK", role: .cancel) { libraryError = nil }
            } message: { Text(libraryError ?? "") }
        }
        .task { cleanupAssets() }
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
        .alert("Shared-set import", isPresented: $notice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Importing .outerview files will be connected in the next implementation pass.")
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
        do { try library.markOpened(id); activeID = id }
        catch { libraryError = error.localizedDescription }
    }

    private var launchScreen: some View {
        HStack(spacing: 0) {
            VStack(spacing: 22) {
                Spacer(minLength: 10)
                Image(systemName: "rectangle.on.rectangle.circle.fill")
                    .font(.system(size: 76)).foregroundStyle(.tint)
                VStack(spacing: 6) {
                    Text("OuterView").font(.system(size: 32, weight: .bold))
                    Text("Interview practice, at your pace.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    welcomeAction("Create a Training Set…", icon: "plus") { draft = SetDraft() }
                    welcomeAction("Import a Shared Set…", icon: "square.and.arrow.down") { notice = true }
                    welcomeAction("Explore a Sample", icon: "play") {
                        let sample = SetDraft.sample
                        do { try library.save(sample); openSet(sample.id) }
                        catch { libraryError = error.localizedDescription }
                    }
                }.padding(.top, 12)
                Spacer(minLength: 10)
                Text("Training sets saved on this Mac")
                    .font(.caption).foregroundStyle(.tertiary)
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
                                                Text("Opened \(opened.formatted(date: .abbreviated, time: .shortened))")
                                                    .font(.caption2).foregroundStyle(.tertiary)
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
                                        Button("Edit…") { draft = set }
                                        Button("Delete…", role: .destructive) { deletion = set }
                                    }
                                Divider().padding(.leading, 52)
                            }
                        }.padding(.horizontal, 8)
                    }
                }
                Text("Most recently opened first")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 20)
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

private struct SetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SetDraft
    @State private var selected = 0
    @State private var pendingRemoval: (() -> Void)?
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
                            ContentUnavailableView("Add a passage from your PDF", systemImage: "crop",
                                description: Text("One rectangular crop per group. PDF selection and cropping will be connected next."))
                                .frame(height: 170)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
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
        .confirmationDialog("Remove this content?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { pendingRemoval?(); pendingRemoval = nil }
        } message: {
            Text("Saving the set will also delete recordings belonging to the removed questions. Cancel the editor to keep the original set.")
        }
    }
}

private struct PracticeWorkspace: View {
    let set: SetDraft
    let goHome: () -> Void
    let edit: () -> Void
    @State private var groupIndex = 0
    @State private var questionIndex: Int?
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
                List(selection: Binding(get: { groupIndex }, set: { groupIndex = $0; questionIndex = nil })) {
                    ForEach(set.groups.indices, id: \.self) { index in
                        Label(set.groups[index].label, systemImage: "rectangle.stack").tag(index)
                    }
                }
                Button("Edit Training Set", systemImage: "pencil", action: edit).padding()
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
                                Text(group.questions[index].text).font(.system(size: 28, weight: .medium))
                                    .textSelection(.enabled)
                            } else {
                                Label("Question hidden", systemImage: "eye.slash").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if showPassage {
                                Label("This group has no passage", systemImage: "doc")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        } else {
                            ContentUnavailableView("Ready when you are", systemImage: "rectangle.stack",
                                description: Text("Start this group to reveal its first question. Take your time before recording."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Divider()
                    VStack(spacing: 20) {
                        RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.4))
                            .frame(width: 212, height: 282)
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: showCamera ? "video" : "video.slash").font(.largeTitle)
                                    Text(showCamera ? "Camera preview" : "Camera hidden").font(.headline)
                                    if showCamera { Text("Available in the recording pass").font(.caption) }
                                }.foregroundStyle(.secondary)
                            }
                            .overlay(alignment: .topTrailing) {
                                visibilityButton("Camera", visible: $showCamera).padding(10)
                            }
                        VStack(spacing: 10) {
                            Text(showTimer ? "00:00" : "—:—")
                                .font(.system(size: 40, weight: .light, design: .monospaced))
                                .accessibilityLabel(showTimer ? "Recording elapsed, zero seconds" : "Timer hidden")
                            Text(showTimer ? "Recording elapsed" : "Timer hidden")
                                .font(.caption).foregroundStyle(.secondary)
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
                    HStack(spacing: 12) {
                        Image(systemName: "film.stack").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(questionIndex == nil ? "Start a question to see its takes" : "No takes for this question yet")
                                .font(.headline)
                            Text("Saved recordings will appear here for playback, retry, and export.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(.vertical, 20)
                } label: {
                    Text("Takes\(questionIndex.map { " · Question \($0 + 1)" } ?? "")").font(.headline)
                }.padding(20)
            }
            .background(.background)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Training Sets", systemImage: "chevron.left", action: goHome)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let index = questionIndex {
                    Button("Previous", systemImage: "chevron.left") { questionIndex = index - 1 }
                        .disabled(index == 0)
                    Button(index == group.questions.count - 1 ? "Finish Group" : "Next", systemImage: "chevron.right") {
                        questionIndex = index + 1 < group.questions.count ? index + 1 : nil
                    }
                    Button("Record", systemImage: "record.circle") { }
                        .disabled(true).help("Recording will be connected in the next implementation pass")
                } else {
                    Button("Start", systemImage: "play.fill") { questionIndex = 0 }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
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

#Preview {
    ContentView().modelContainer(for: [TrainingSet.self, PassageGroup.self, Question.self, Take.self], inMemory: true)
}
