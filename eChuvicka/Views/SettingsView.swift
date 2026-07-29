import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Detekce zvuku (VOX)", isOn: $settings.isVOXEnabled)
                
                if settings.isVOXEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Citlivost")
                            Spacer()
                            Text("\(Int(settings.voxSensitivity * 100)) %")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.voxSensitivity, in: 0...1)
                        
                        Picker("Doba vysílání po detekci", selection: $settings.voxHoldTime) {
                            Text("5 sekund").tag(5.0)
                            Text("15 sekund").tag(15.0)
                            Text("30 sekund").tag(30.0)
                            Text("1 minuta").tag(60.0)
                        }
                    }
                }
                
                Toggle("Zesílit příjem zvuku (Audio Boost 2x)", isOn: $settings.isAudioBoostEnabled)
                
                Text("Funkce VOX automaticky aktivuje přenos zvuku pouze při detekci hluku, což výrazně šetří baterii. Audio Boost softwarově zesílí tichý zvuk z dětské jednotky.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Přenos zvuku")
            }
            
            Section {
                Toggle("Alarm při ztrátě spojení", isOn: $settings.isDisconnectAlarmEnabled)
                
                if settings.isDisconnectAlarmEnabled {
                    Picker("Prodleva alarmu", selection: $settings.disconnectAlarmDelay) {
                        Text("Okamžitě (6 sekund)").tag(6.0)
                        Text("15 sekund").tag(15.0)
                        Text("30 sekund").tag(30.0)
                        Text("1 minuta").tag(60.0)
                    }
                }
                
                Toggle("Varování při nízké baterii dítěte (< 20 %)", isOn: $settings.isLowBatteryAlertEnabled)
                
                Toggle("Automatické znovupřipojení", isOn: $settings.isAutoReconnectEnabled)
                
                Text("Prodleva alarmu zabraňuje falešným poplachům při krátkých výpadcích Wi-Fi. Automatické znovupřipojení se pokusí samo navázat spojení bez nutnosti psát PIN.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Upozornění a spojení (Rodič)")
            }
            
            Section {
                Toggle("Vyžadovat párovací PIN", isOn: $settings.isPinRequired)
                
                Toggle("Automatický noční režim (zčernání displeje)", isOn: $settings.isAutoNightModeEnabled)
                
                Text("Pokud zrušíte vyžadování PINu, k chůvičce se bude moci na stejné síti připojit kdokoliv. Pokud je funkce aktivní, 10 sekund po úspěšném připojení se obrazovka dětské jednotky zcela zhasne.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Displej a zabezpečení (Dítě)")
            }
            
            Section {
                HStack {
                    Text("Verze aplikace")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("eChůvička")
                        .font(.headline)
                    Text("Spolehlivá multiplatformní chůvička pro vaše zařízení.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("O aplikaci")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nastavení")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 600)
        #endif
    }
}
