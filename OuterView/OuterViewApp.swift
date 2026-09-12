import SwiftUI

@main
struct OuterViewApp: App {
    var body: some Scene {
        Window("OuterView", id: "main") {
            ContentView()
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
