import SwiftUI

struct SettingsView: View {
    @Environment(TorrentManager.self) private var manager
    @AppStorage("serverURL") private var serverURL = "http://localhost:9091"
    @AppStorage("username") private var username = ""
    @AppStorage("password") private var password = ""
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some View {
        Form {
            Section("Transmission Server") {
                TextField("Server URL", text: $serverURL, prompt: Text("http://hostname:9091"))
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Button("Connect") {
                    manager.reconnect()
                }
            }

            Section("General") {
                Toggle("Show menu bar icon", isOn: $showMenuBarExtra)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}
