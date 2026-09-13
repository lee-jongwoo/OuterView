import SwiftUI
import SwiftData

@main
struct OuterViewApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycle
    @State private var windows = TrainingWindows()
    private let library: Result<ModelContainer, Error> = Result {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appending(path: "OuterView", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: TrainingLibrary.schema,
                                               url: directory.appending(path: "Library.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: TrainingLibrary.schema, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }

    var body: some Scene {
        Window("OuterView", id: "main") {
            switch library {
            case .success(let container):
                ContentView().environment(windows).modelContainer(container)
            case .failure(let error):
                ContentUnavailableView("Couldn’t Open Your Library", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your existing files have not been removed. Quit and reopen the app to retry.\n\n" + error.localizedDescription))
                    .frame(width: 620, height: 360)
            }
        }
        .defaultSize(width: 820, height: 520)
        .windowResizability(.contentSize)

        Window("Training", id: "training") {
            if case .success(let container) = library {
                TrainingWindow().environment(windows).modelContainer(container)
            }
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            VisibilitySettings()
        }
    }
}

private struct VisibilitySettings: View {
    @AppStorage("exportQuality") private var exportQuality = ExportQuality.balanced.rawValue
    @AppStorage("showPassage") private var showPassage = true
    @AppStorage("showQuestion") private var showQuestion = true

    var body: some View {
        Form {
            Section {
                Toggle("Show passages", isOn: $showPassage)
                Toggle("Show question text", isOn: $showQuestion)
            } header: {
                Text("Practice Content")
            } footer: {
                Text("Applies to all training sets during practice. Content is only shown after you reach its reveal stage.")
            }
            Section("Video Export") {
                Picker("Default quality", selection: $exportQuality) {
                    ForEach(ExportQuality.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 320)
        .navigationTitle("Settings")
    }
}

@Observable
final class TrainingWindows {
    var set: SetDraft?
    var sessionID = UUID()
    var recovered = false
}

struct TrainingWindow: View {
    @Environment(TrainingWindows.self) private var windows
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var draft: SetDraft?
    @State private var revision = 0
    @State private var error: String?

    var body: some View {
        Group {
            if let set = windows.set {
                PracticeWorkspace(set: set, goHome: {
                    openWindow(id: "main")
                    dismissWindow(id: "training")
                }, edit: { draft = set })
                .id("\(windows.sessionID)-\(revision)")
                .navigationTitle(set.title)
            } else {
                ContentUnavailableView("Open a Training Set", systemImage: "rectangle.stack")
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .sheet(item: $draft) { value in
            SetEditor(initial: value) { saved in
                do {
                    let library = TrainingLibrary(context: modelContext)
                    try library.save(saved)
                    windows.set = saved
                    revision += 1
                    draft = nil
                    try library.cleanupAssets(AssetStorage.applicationStorage())
                } catch { self.error = error.localizedDescription }
            }
            .alert("Couldn’t Save Set", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
        .onDisappear { windows.set = nil }
    }
}
