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
                            AudioLevelView(audioLevel: coordinator.audioLevel, isTransmitting: coordinator.isConnected && coordinator.audioLevel > 0.05)
                                .frame(height: 200)
                            
                            if coordinator.audioLevel <= 0.05 && coordinator.isConnected {
                                Image(systemName: "powersleep")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        
                        // Status Text
                        VStack(spacing: 8) {
                            if coordinator.isConnected {
                                if coordinator.audioLevel > 0.05 {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 10, height: 10)
                                        Text("VYSÍLÁ ZVUK")
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    Text("Ticho – úspora baterie")
                                        .font(.system(.body, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                // Parent speaking indicator
                                if coordinator.isConnectionAlive && false /* replace with isParentSpeaking */ {
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
