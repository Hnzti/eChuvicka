import SwiftUI

struct ConnectionStatusBadge: View {
    var mode: ConnectionMode
    var latencyMs: Double
    
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
            
            Text(mode.rawValue)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.primary)
            
            if mode == .connectedDirect || mode == .connectedRouter {
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Odezva: \(Int(latencyMs))ms")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    private var dotColor: Color {
        switch mode {
        case .disconnected: return .red
        case .searching: return .yellow
        case .connectedDirect, .connectedRouter: return .green
        }
    }
    
    private var isPulsing: Bool {
        mode == .searching
    }
}
