import SwiftUI

struct ChildView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var isNightModeActive = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        coordinator.stop()
                        coordinator.role = .none
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Zpět")
                        }
                        .font(.system(.body, design: .rounded, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.indigo)
                    
                    Spacer()
                    
                    Text("Dětská jednotka")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    
                    Spacer()
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(.body, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.indigo)
                    .navigationDestination(isPresented: $showingSettings) {
                        SettingsView()
                    }
                }
                .layoutPriority(1)
                .padding()
                #if os(iOS)
                .background(Color.black.opacity(0.05).ignoresSafeArea(edges: .top))
                #else
                .background(Color.black.opacity(0.05))
                #endif
                
                ScrollView {
                    VStack(spacing: 40) {
                        // PIN Display
                        VStack(spacing: 12) {
                            if coordinator.appSettings.isPinRequired {
                                Text("Párovací PIN kód")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Text(coordinator.generatedPIN.isEmpty ? "----" : coordinator.generatedPIN)
                                    .font(.system(size: 54, weight: .black, design: .monospaced))
                                    .tracking(8)
                                    .padding(.vertical, 20)
                                    .padding(.horizontal, 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                    )
                            } else {
                                Text("Otevřené spojení (bez PINu)")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Status Badge
                        ConnectionStatusBadge(
                            mode: coordinator.connectionMode,
                            latencyMs: coordinator.latencyMs
                        )
                        
                        // Audio Visualizer
                        ZStack {
                            AudioLevelView(audioLevel: coordinator.audioLevel, isCapturing: coordinator.isConnected, isTransmitting: coordinator.audioManager.isTransmitting)
                                .frame(height: 200)
                        }
                        
                        // Status Text
                        VStack(spacing: 8) {
                            if coordinator.isConnected {
                                if coordinator.audioManager.isTransmitting {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 12, height: 12)
                                        Text("PŘENÁŠÍ ZVUK K RODIČI!")
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                            .foregroundColor(.orange)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 10, height: 10)
                                        Text("MIKROFON JE ZAPNUTÝ")
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                // Parent speaking indicator
                                if coordinator.isParentSpeaking {
                                    Text("Rodič mluví...")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.top, 4)
                                }
                            } else {
                                Text("Čekání na spojení...")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            } // Ends VStack
            
            // Night mode overlay in ZStack
            if isNightModeActive {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isNightModeActive = false
                        }
                    }
            }
        } // Ends ZStack
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .statusBarHidden(isNightModeActive)
        #endif
        .onChange(of: coordinator.isConnected) { _, isConnected in
            if isConnected && coordinator.appSettings.isAutoNightModeEnabled {
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if coordinator.isConnected {
                        withAnimation {
                            isNightModeActive = true
                        }
                    }
                }
            } else {
                withAnimation {
                    isNightModeActive = false
                }
            }
        }
    } // Ends body
}
