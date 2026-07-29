import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Přenos zvuku")) {
                    Toggle("Detekce zvuku (VOX - úspora baterie)", isOn: $settings.isVOXEnabled)
                    
                    if settings.isVOXEnabled {
                        VStack(alignment: .leading) {
                            Text("Citlivost detekce: \(Int(settings.voxSensitivity * 100))%")
                            Slider(value: $settings.voxSensitivity, in: 0.05...0.5)
                        }
                    }
                }
                
                Section(header: Text("Bezpečnost a Alerting")) {
                    Toggle("Alarm při ztrátě signálu", isOn: $settings.isDisconnectAlarmEnabled)
                }
            }
            .navigationTitle("Nastavení")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
    }
}
