import SwiftUI

struct ConnectionStatusBadge: View {
    var mode: ConnectionMode
    var latencyMs: Double
    /// Wi‑Fi RSSI in dBm when available (macOS). Always `nil` on iPhone/iPad.
    var wifiRSSIDbm: Int? = nil
    
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .opacity(isPulsing ? (pulse ? 0.4 : 1.0) : 1.0)
                .onAppear {
                    if isPulsing {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                }
                .onChange(of: mode) { _, newMode in
                    if newMode == .searching {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    } else {
                        withAnimation {
                            pulse = false
                        }
                    }
                }
            
            Text(mode.localizedTitle)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.primary)
            
            if mode == .connectedDirect || mode == .connectedLocalNetwork {
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(L10n.Connection.latency(Int(latencyMs)))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(latencyColor)
                
                if let wifiRSSIDbm {
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(L10n.Connection.signal(wifiRSSIDbm))
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundColor(rssiColor(wifiRSSIDbm))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
    
    private var accessibilityText: String {
        var parts = [mode.localizedTitle]
        if mode == .connectedDirect || mode == .connectedLocalNetwork {
            parts.append(L10n.Connection.a11yLatency(Int(latencyMs)))
            if let wifiRSSIDbm {
                parts.append(L10n.Connection.a11ySignal(wifiRSSIDbm))
            }
        }
        return parts.joined(separator: ", ")
    }
    
    private var latencyColor: Color {
        switch latencyMs {
        case ..<80: return .secondary
        case ..<200: return .orange
        default: return .red
        }
    }
    
    private func rssiColor(_ dbm: Int) -> Color {
        switch dbm {
        case (-55)...: return .green
        case (-70)..<(-55): return .secondary
        case (-80)..<(-70): return .orange
        default: return .red
        }
    }
    
    private var dotColor: Color {
        switch mode {
        case .disconnected: return .red
        case .searching: return .yellow
        case .connectedDirect, .connectedLocalNetwork:
            return latencyMs < 200 ? .green : .orange
        }
    }
    
    private var isPulsing: Bool {
        mode == .searching
    }
}
