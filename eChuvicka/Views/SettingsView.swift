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
                    }
                }
                
                Text("Funkce VOX (Voice Operated eXchange) automaticky aktivuje přenos zvuku pouze při detekci hluku. To výrazně šetří baterii a snižuje šum na pozadí.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Přenos zvuku")
            }
            
            Section {
                Toggle("Alarm při ztrátě spojení", isOn: $settings.isDisconnectAlarmEnabled)
                
                Text("Spustí hlasitý alarm na rodičovské jednotce při ztrátě spojení s dětskou jednotkou.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Upozornění")
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
        .frame(minWidth: 400, minHeight: 450)
        #endif
    }
}
