import SwiftUI

struct SettingsView: View {
    @Environment(TorrentManager.self) private var manager
    @AppStorage("serverURL") private var serverURL = "http://localhost:9091"
    @AppStorage("username") private var username = ""
    @AppStorage("password") private var password = ""
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("notifyOnCompletion") private var notifyOnCompletion = true
    @AppStorage("pollInterval") private var pollInterval: Double = 5.0

    @State private var speedLimitDown = 0
    @State private var speedLimitDownEnabled = false
    @State private var speedLimitUp = 0
    @State private var speedLimitUpEnabled = false
    @State private var altSpeedDown = 0
    @State private var altSpeedUp = 0
    @State private var altSpeedEnabled = false
    @State private var altSpeedTimeEnabled = false
    @State private var altSpeedTimeBegin = 0
    @State private var altSpeedTimeEnd = 0
    @State private var altSpeedTimeDay = 127
    @State private var speedSettingsLoaded = false

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
                LabeledContent("Refresh interval") {
                    HStack(spacing: 2) {
                        TextField("", value: $pollInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("seconds")
                    }
                }
                Toggle("Show menu bar icon", isOn: $showMenuBarExtra)
                Toggle("Notify when downloads complete", isOn: $notifyOnCompletion)
            }

            Section("Speed Limits") {
                Toggle("Limit download speed", isOn: $speedLimitDownEnabled)
                if speedLimitDownEnabled {
                    LabeledContent("Download limit") {
                        HStack(spacing: 2) {
                            TextField("", value: $speedLimitDown, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("KB/s")
                        }
                    }
                }
                Toggle("Limit upload speed", isOn: $speedLimitUpEnabled)
                if speedLimitUpEnabled {
                    LabeledContent("Upload limit") {
                        HStack(spacing: 2) {
                            TextField("", value: $speedLimitUp, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("KB/s")
                        }
                    }
                }
            }

            Section("Turtle Mode (Alternative Speeds)") {
                Toggle("Enable turtle mode", isOn: $altSpeedEnabled)
                LabeledContent("Download limit") {
                    HStack(spacing: 2) {
                        TextField("", value: $altSpeedDown, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("KB/s")
                    }
                }
                LabeledContent("Upload limit") {
                    HStack(spacing: 2) {
                        TextField("", value: $altSpeedUp, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("KB/s")
                    }
                }
                Toggle("Use scheduled times", isOn: $altSpeedTimeEnabled)
                if altSpeedTimeEnabled {
                    LabeledContent("From") {
                        HStack(spacing: 2) {
                            TextField("", value: $altSpeedTimeBegin, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("To")
                            TextField("", value: $altSpeedTimeEnd, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("min past midnight")
                        }
                    }
                }
                Button("Apply Speed Settings") {
                    Task {
                        var args = SessionSetArgs()
                        args.speedLimitDown = speedLimitDown
                        args.speedLimitDownEnabled = speedLimitDownEnabled
                        args.speedLimitUp = speedLimitUp
                        args.speedLimitUpEnabled = speedLimitUpEnabled
                        args.altSpeedDown = altSpeedDown
                        args.altSpeedUp = altSpeedUp
                        args.altSpeedEnabled = altSpeedEnabled
                        args.altSpeedTimeEnabled = altSpeedTimeEnabled
                        args.altSpeedTimeBegin = altSpeedTimeBegin
                        args.altSpeedTimeEnd = altSpeedTimeEnd
                        args.altSpeedTimeDay = altSpeedTimeDay
                        await manager.updateSessionSettings(args)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .onChange(of: manager.sessionSettings?.altSpeedEnabled) {
            loadSpeedSettings()
        }
        .task {
            loadSpeedSettings()
        }
    }

    private func loadSpeedSettings() {
        guard let s = manager.sessionSettings, !speedSettingsLoaded else { return }
        speedLimitDown = s.speedLimitDown
        speedLimitDownEnabled = s.speedLimitDownEnabled
        speedLimitUp = s.speedLimitUp
        speedLimitUpEnabled = s.speedLimitUpEnabled
        altSpeedDown = s.altSpeedDown
        altSpeedUp = s.altSpeedUp
        altSpeedEnabled = s.altSpeedEnabled
        altSpeedTimeEnabled = s.altSpeedTimeEnabled
        altSpeedTimeBegin = s.altSpeedTimeBegin
        altSpeedTimeEnd = s.altSpeedTimeEnd
        altSpeedTimeDay = s.altSpeedTimeDay
        speedSettingsLoaded = true
    }
}
