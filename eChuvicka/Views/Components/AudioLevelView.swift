import SwiftUI

struct AudioLevelView: View {
    var audioLevel: Float
    var isTransmitting: Bool
    
    @State private var phase: CGFloat = 0
    
    var body: some View {
        let level = CGFloat(min(max(audioLevel, 0), 1))
        let isActive = isTransmitting && level > 0.01
        
        let color: Color = level > 0.7 ? .red : (level > 0.4 ? .orange : .blue)
        
        ZStack {
            // Background circles
            ForEach(0..<3) { i in
                Circle()
                    .stroke(color.opacity(isActive ? (0.3 - CGFloat(i) * 0.1) : 0.05), lineWidth: 2)
                    .frame(
                        width: 100 + (isActive ? level * 150 : 0) + CGFloat(i) * 40,
                        height: 100 + (isActive ? level * 150 : 0) + CGFloat(i) * 40
                    )
                    .scaleEffect(isActive ? (1.0 + (level * 0.2)) : 1.0)
                    .animation(
                        isActive ? .linear(duration: 0.1 + Double(i)*0.05) : .spring(response: 0.5, dampingFraction: 0.7),
                        value: level
                    )
            }
            
            // Inner core
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            isActive ? color : Color.secondary.opacity(0.2),
                            isActive ? color.opacity(0.7) : Color.secondary.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .scaleEffect(isActive ? 1.0 + (level * 0.3) : 1.0)
                .shadow(color: isActive ? color.opacity(0.5) : .clear, radius: 10 * level, x: 0, y: 0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: level)
                .animation(.easeInOut(duration: 0.3), value: isActive)
        }
    }
}
