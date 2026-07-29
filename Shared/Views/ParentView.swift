import SwiftUI

struct ParentView: View {
    @ObservedObject var networkManager: NetworkManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var settings: AppSettings
    @Binding var role: AppRole
    
    @State private var pinInput: String = ""
    
    var body: some View {
        VStack(spacing: 25) {
            HStack {
                Button("Zpět") {
                    networkManager.stop()
                    role = .none
                }
                Spacer()
                Text("Rodičovská Jednotka")
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            if !networkManager.isConnected {
                VStack(spacing: 15) {
                    Text("Zadejte 6místný PIN dítěte:")
                        .font(.headline)
                    
                    TextField("000000", text: $pinInput)
                        .keyboardType(.numberPad)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 200)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    
                    Button("Připojit k dítěti") {
                        if pinInput.count == 6 {
                            networkManager.startBrowsing(targetPIN: pinInput)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pinInput.count != 6)
                }
            } else {
                VStack(spacing: 20) {
                    Text("Připojeno přes: \(networkManager.connectionMode.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    // Push to talk button
                    Button(action: {}) {
                        VStack {
                            Image(systemName: "mic.fill")
                                .font(.largeTitle)
                            Text("Mluvit na dítě")
                                .bold()
                        }
                        .padding()
                        .frame(width: 200, height: 200)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                    }
                    
                    Spacer()
                }
            }
            Spacer()
        }
    }
}
