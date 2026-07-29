import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.indigo)
                Text("eChůvička")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 20)

            ViewThatFits {
                HStack(spacing: 20) {
                    cards
                }
                VStack(spacing: 20) {
                    cards
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 30)
        }
    }
    
    @ViewBuilder
    var cards: some View {
        RoleCard(
            title: "Dítě",
            subtitle: "Vysílač zvuku",
            iconName: "figure.and.child.holdinghands",
            gradientColors: [.blue, .indigo]
        ) {
            coordinator.startAsChild()
        }
        
        RoleCard(
            title: "Rodič",
            subtitle: "Přijímač zvuku",
            iconName: "ear",
            gradientColors: [.green, .teal]
        ) {
            coordinator.role = .parent
        }
    }
}

struct RoleCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let gradientColors: [Color]
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(.white)
                    .frame(height: 70)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: gradientColors[0].opacity(0.3), radius: 10, x: 0, y: 5)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
