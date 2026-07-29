import SwiftUI

@main
struct eChuvickaApp: App {
    @StateObject private var coordinator = SessionCoordinator()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.appSettings)
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 600)
                #endif
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @State private var showingSettings = false
    
    var body: some View {
        Group {
            switch coordinator.role {
            case .none:
                RoleSelectionView(showingSettings: $showingSettings)
                    .transition(.opacity.combined(with: .scale))
            case .child:
                ChildView()
                    .transition(.move(edge: .trailing))
            case .parent:
                ParentView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: coordinator.role)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(coordinator.appSettings)
                #if os(macOS)
                .frame(width: 400, height: 500)
                #endif
        }
    }
}
