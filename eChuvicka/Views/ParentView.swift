import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ParentView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @State private var pin: String = ""
    @State private var isPressingPTT = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    coordinator.stop()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Zpět")
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.teal)
                
                Spacer()
                
                Text("Rodičovská jednotka")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                
                Spacer()
                
                Text("Zpět").opacity(0)
            }
            .padding()
            .background(Color.black.opacity(0.05).ignoresSafeArea(edges: .top))
            
            if !coordinator.isConnected {
                // PIN Entry Screen
                VStack(spacing: 30) {
                    Spacer()
                    
                    Text("Zadejte PIN z dětské jednotky")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    
                    PINEntryView(pin: $pin)
                    
                    Button(action: {
                        coordinator.startAsParent(pin: pin)
                    }) {
                        Text("Připojit")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 300)
                            .padding(.vertical, 16)
                            .background(
                                pin.count == 6 ? Color.teal : Color.gray.opacity(0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(pin.count < 6)
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding()
            } else {
                // Connected Monitoring Screen
                VStack(spacing: 30) {
                    if !coordinator.isConnectionAlive {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Spojení ztraceno!")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    ConnectionStatusBadge(
                        mode: coordinator.connectionMode,
                        latencyMs: coordinator.latencyMs
                    )
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    // Audio Visualizer
                    ZStack {
                        AudioLevelView(audioLevel: coordinator.audioLevel, isTransmitting: coordinator.audioLevel > 0.05)
                            .frame(height: 250)
                        
                        if coordinator.audioLevel <= 0.05 {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    
                    // Child Battery
                    HStack(spacing: 8) {
                        Image(systemName: batteryIcon(for: coordinator.peerBatteryLevel))
                            .foregroundColor(batteryColor(for: coordinator.peerBatteryLevel))
                        Text("Baterie dítěte: \(Int(coordinator.peerBatteryLevel * 100)) %")
                            .font(.system(.body, design: .rounded, weight: .medium))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // PTT Button
                    VStack(spacing: 12) {
                        Text("Podržte pro mluvení")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            Circle()
                                .fill(isPressingPTT ? Color.red : Color.teal)
                                .frame(width: 100, height: 100)
                                .shadow(color: (isPressingPTT ? Color.red : Color.teal).opacity(0.4), radius: 10, x: 0, y: 5)
                            
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        .scaleEffect(isPressingPTT ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressingPTT)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isPressingPTT {
                                        #if os(iOS)
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        #endif
                                        isPressingPTT = true
                                        coordinator.startPTT()
                                    }
                                }
                                .onEnded { _ in
                                    isPressingPTT = false
                                    coordinator.stopPTT()
                                }
                        )
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .animation(.default, value: coordinator.isConnected)
        .animation(.default, value: coordinator.isConnectionAlive)
    }
    
    private func batteryIcon(for level: Float) -> String {
        if level > 0.8 { return "battery.100" }
        if level > 0.5 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }
    
    private func batteryColor(for level: Float) -> Color {
        if level <= 0.2 { return .red }
        if level <= 0.4 { return .yellow }
        return .green
    }
}

struct PINEntryView: View {
    @Binding var pin: String
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { index in
                PINBox(
                    character: pin.count > index ? String(pin[pin.index(pin.startIndex, offsetBy: index)]) : "",
                    isActive: pin.count == index
                )
            }
        }
        .overlay(
            TextField("", text: $pin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.01) // Nearly invisible but still tappable
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: pin) { _, newValue in
                    var filtered = newValue.filter { $0.isNumber }
                    if filtered.count > 6 {
                        filtered = String(filtered.prefix(6))
                    }
                    if filtered != pin {
                        pin = filtered
                    }
                }
        )
        .frame(height: 70)
    }
}

struct PINBox: View {
    let character: String
    let isActive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
            
            if isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.teal, lineWidth: 2)
            }
            
            Text(character)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
        }
        .frame(width: 50, height: 60)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
