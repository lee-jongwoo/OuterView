import SwiftUI
import SwiftData

@main
struct OuterViewApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycle
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
                ContentView().modelContainer(container)
            case .failure(let error):
                ContentUnavailableView("Couldn’t Open Your Library", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your existing files have not been removed. Quit and reopen the app to retry.\n\n" + error.localizedDescription))
                    .frame(width: 620, height: 360)
            }
        }
        .defaultSize(width: 820, height: 520)
        .windowResizability(.contentSize)

        Settings {
            VisibilitySettings()
        }
    }
}

private struct VisibilitySettings: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 220)
        .navigationTitle("Settings")
    }
}
