import SwiftUI

struct PracticeWorkspace: View {
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
                    Button("Previous", systemImage: "chevron.left") { progress.previous(hasPassage: group.imagePath != nil) }
                        .disabled(index == 0 && group.imagePath == nil)
                    Button(index == group.questions.count - 1 ? "Finish Group" : "Next", systemImage: "chevron.right") {
                        progress.next(questionCount: group.questions.count)
                    }
                    Button("Record", systemImage: "record.circle") { }
                        .disabled(true).help("Recording will be connected in the next implementation pass")
                } else if progress.stage == .reading {
                    Button("Next", systemImage: "chevron.right") { progress.next(questionCount: group.questions.count) }
                } else {
                    Button("Start", systemImage: "play.fill") { progress.start(hasPassage: group.imagePath != nil) }
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

