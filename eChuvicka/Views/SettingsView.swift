import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    
    let role: AppRole
    let onCommitDeviceName: () -> Void
    var onPinRequirementChange: () -> Void = {}
    
    @State private var deviceNameDraft = ""
    @FocusState private var isDeviceNameFocused: Bool
    
    init(
        role: AppRole = .none,
        onCommitDeviceName: @escaping () -> Void = {},
        onPinRequirementChange: @escaping () -> Void = {}
    ) {
        self.role = role
        self.onCommitDeviceName = onCommitDeviceName
        self.onPinRequirementChange = onPinRequirementChange
    }

    var body: some View {
        Form {
            Section {
                TextField(L10n.Settings.deviceName, text: $deviceNameDraft)
                    .focused($isDeviceNameFocused)
                    .submitLabel(.done)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit {
                        commitDeviceName()
                        isDeviceNameFocused = false
                    }
            } header: {
                Text(L10n.Settings.device)
            }

            Section {
                Picker(L10n.Settings.language, selection: $settings.appLanguage) {
                    Text(L10n.Settings.languageSystem).tag(AppLanguage.system)
                    Text("Čeština").tag(AppLanguage.czech)
                    Text("English").tag(AppLanguage.english)
                }

                Text(L10n.Settings.languageHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.Settings.language)
            }
            
            Section {
                Toggle(L10n.Settings.vox, isOn: $settings.isVOXEnabled)
                
                Text(L10n.Settings.voxHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settings.isVOXEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Settings.sensitivity)
                            Spacer()
                            Text("\(Int(settings.voxSensitivity * 100)) %")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.voxSensitivity, in: 0...1)
                        
                        HStack {
                            Text(L10n.Settings.holdAfterDetection)
                            Spacer()
                            Text("\(Int(settings.voxHoldTime)) s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.voxHoldTime, in: 5...30, step: 1)
                    }
                }
            } header: {
                Text(L10n.Settings.audio)
            }
            
            Section {
                Toggle(L10n.Settings.disconnectAlarm, isOn: $settings.isDisconnectAlarmEnabled)
                
                if settings.isDisconnectAlarmEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Settings.alarmDelay)
                            Spacer()
                            Text("\(Int(settings.disconnectAlarmDelay)) s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.disconnectAlarmDelay, in: 5...30, step: 1)
                        
                        Text(L10n.Settings.disconnectAlarmHelp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(L10n.Settings.lowBatteryAlert, isOn: $settings.isLowBatteryAlertEnabled)
                
                if settings.isLowBatteryAlertEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Settings.batteryThreshold)
                            Spacer()
                            Text("\(Int(settings.lowBatteryThreshold * 100)) %")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.lowBatteryThreshold, in: 0.05...0.30, step: 0.05)
                        
                        Text(L10n.Settings.lowBatteryHelp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(L10n.Settings.autoReconnect, isOn: $settings.isAutoReconnectEnabled)
                
                Text(L10n.Settings.autoReconnectHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.Settings.alerts)
            }
            
            if role == .child {
                Section {
                    Toggle(L10n.Settings.requirePin, isOn: $settings.isPinRequired)
                        .onChange(of: settings.isPinRequired) { _, _ in
                            settings.synchronize()
                            onPinRequirementChange()
                        }
                    
                    Text(L10n.Settings.pinHelp(AppBrand.displayName))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text(L10n.Settings.security)
                }
            }
            
            Section {
                HStack {
                    Text(L10n.Settings.version)
                    Spacer()
                    Text(appVersionLabel)
                        .foregroundColor(.secondary)
                }
                
                Text("© \(Calendar.current.component(.year, from: Date())) \(AppBrand.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.Settings.about)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.Settings.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.Common.done) {
                    commitDeviceName()
                    isDeviceNameFocused = false
                }
                .fontWeight(.semibold)
            }
        }
        #endif
        .onAppear {
            deviceNameDraft = settings.deviceName
        }
        .onDisappear {
            commitDeviceName()
            settings.synchronize()
        }
    }
    
    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
    
    private func commitDeviceName() {
        let trimmed = deviceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if deviceNameDraft != trimmed {
            deviceNameDraft = trimmed
        }
        guard trimmed != settings.deviceName else { return }
        settings.deviceName = trimmed
        onCommitDeviceName()
    }
}
