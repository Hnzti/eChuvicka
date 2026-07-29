import SwiftUI

struct ChildView: View {
    @ObservedObject var networkManager: NetworkManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var settings: AppSettings
    @Binding var role: AppRole
    
    var body: some View {
        VStack(spacing: 25) {
            HStack {
                Button("Zpět") {
                    networkManager.stop()
                    audioManager.stop()
                    role = .none
                }
                Spacer()
                Text("Dětská Jednotka")
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            VStack(spacing: 10) {
                Text("Párovací PIN kód:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(networkManager.generatedPIN)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            VStack(spacing: 8) {
                Text("Režim připojení: \(networkManager.connectionMode.rawValue)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                HStack {
                    Circle()
                        .fill(audioManager.isTransmitting ? Color.red : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(audioManager.isTransmitting ? "VYSÍLÁ ZVUK" : "Ticho (VOX úspora)")
                        .font(.caption)
                        .bold()
                }
            }
            
            Spacer()
        }
        .onAppear {
            networkManager.startHost(pin: networkManager.generatedPIN)
            audioManager.startRecording(voxEnabled: settings.isVOXEnabled, threshold: Float(settings.voxSensitivity))
        }
    }
}
