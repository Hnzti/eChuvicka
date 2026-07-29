import SwiftUI

struct RoleSelectionView: View {
    @Binding var selectedRole: AppRole
    
    var body: some View {
        VStack(spacing: 30) {
            Text("eChůvička")
                .font(.largeTitle)
                .bold()
            
            Text("Vyberte roli tohoto zařízení:")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                Button(action: { selectedRole = .child }) {
                    VStack(spacing: 15) {
                        Image(systemName: "figure.wave")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                        Text("Dítě")
                            .font(.title2)
                            .bold()
                        Text("Vysílač zvuku")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(20)
                }
                
                Button(action: { selectedRole = .parent }) {
                    VStack(spacing: 15) {
                        Image(systemName: "ear")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                        Text("Rodič")
                            .font(.title2)
                            .bold()
                        Text("Přijímač zvuku")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
