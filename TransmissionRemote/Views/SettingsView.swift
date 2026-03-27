import SwiftUI

struct SettingsView: View {
    @Environment(TorrentManager.self) private var manager
    @AppStorage("serverURL") private var serverURL = "http://localhost:9091"
    @AppStorage("username") private var username = ""
    @AppStorage("password") private var password = ""
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("notifyOnCompletion") private var notifyOnCompletion = true
    @AppStorage("pollInterval") private var pollInterval: Double = 5.0

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
                HStack(alignment: .firstTextBaseline) {
                    Text("Refresh interval")
                    Spacer()
                    TextField("", value: $pollInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("seconds")
                }
                Toggle("Show menu bar icon", isOn: $showMenuBarExtra)
                Toggle("Notify when downloads complete", isOn: $notifyOnCompletion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}
