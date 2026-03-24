import SwiftUI

@main
struct TransmissionOpenerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("Transmission Opener", id: "main") {
            StatusView(appState: appState)
                .onOpenURL { url in
                    appState.handleFile(url: url)
                }
        }
        .defaultSize(width: 400, height: 250)

        Settings {
            SettingsView()
        }
    }
}
