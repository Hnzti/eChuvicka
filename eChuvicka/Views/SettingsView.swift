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
                TextField("Název zařízení", text: $deviceNameDraft)
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
                
                Toggle("Automaticky vypnout displej", isOn: $settings.isAutoNightModeEnabled)
                
                if settings.isAutoNightModeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Vypnout po")
                            Spacer()
                            Text("\(Int(settings.displayOffDelay)) s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.displayOffDelay, in: 5...30, step: 1)
                        
                        Text("Displej dětské jednotky zčerná, ale nezamkne se. Klepnutím se znovu rozsvítí.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Displej")
            }
            
            Section {
                Toggle("VOX", isOn: $settings.isVOXEnabled)
                
                Text("VOX spustí přenos zvuku jen při detekci hluku. Když je vypnutý, dětská jednotka vysílá nepřetržitě.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settings.isVOXEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Citlivost")
                            Spacer()
                            Text("\(Int(settings.voxSensitivity * 100)) %")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.voxSensitivity, in: 0...1)
                        
                        HStack {
                            Text("Doba vysílání po detekci")
                            Spacer()
                            Text("\(Int(settings.voxHoldTime)) s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.voxHoldTime, in: 5...30, step: 1)
                    }
                }
            } header: {
                Text("Přenos zvuku")
            }
            
            Section {
                Toggle("Alarm při ztrátě spojení", isOn: $settings.isDisconnectAlarmEnabled)
                
                if settings.isDisconnectAlarmEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Prodleva alarmu")
                            Spacer()
                            Text("\(Int(settings.disconnectAlarmDelay)) s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.disconnectAlarmDelay, in: 5...30, step: 1)
                    }
                }
                
                Toggle("Varování při nízké baterii dítěte", isOn: $settings.isLowBatteryAlertEnabled)
                
                if settings.isLowBatteryAlertEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Práh baterie")
                            Spacer()
                            Text("\(Int(settings.lowBatteryThreshold * 100)) %")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.lowBatteryThreshold, in: 0.05...0.30, step: 0.05)
                    }
                }
                
                Toggle("Obnovit spojení automaticky", isOn: $settings.isAutoReconnectEnabled)
                
                Text("Po krátkém výpadku Wi‑Fi se rodičovská jednotka sama znovu připojí k poslední dětské jednotce, bez opětovného zadání PINu.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Upozornění a spojení")
            }
            
            if role == .child {
                Section {
                    Toggle("Vyžadovat párovací PIN", isOn: $settings.isPinRequired)
                        .onChange(of: settings.isPinRequired) { _, _ in
                            onPinRequirementChange()
                        }
                    
                    Text("Bez PINu se na stejné síti může k dětské jednotce připojit kdokoliv s aplikací eChůvička. Změna se projeví hned ve vysílání dětské jednotky.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Zabezpečení")
                }
            }
            
            Section {
                HStack {
                    Text("Verze aplikace")
                    Spacer()
                    Text("1.1.0")
                        .foregroundColor(.secondary)
                }
                
                Text("© \(Calendar.current.component(.year, from: Date())) eChůvička")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("O aplikaci")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nastavení")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hotovo") {
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
        }
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
