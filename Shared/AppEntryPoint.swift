import SwiftUI

@main
struct eChuvickaApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var audioManager = AudioManager()
    
    @State private var selectedRole: AppRole = .none
    @State private var showSettings: Bool = false
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ZStack {
                    switch selectedRole {
                    case .none:
                        RoleSelectionView(selectedRole: $selectedRole)
                    case .child:
                        ChildView(networkManager: networkManager, audioManager: audioManager, settings: settings, role: $selectedRole)
                    case .parent:
                        ParentView(networkManager: networkManager, audioManager: audioManager, settings: settings, role: $selectedRole)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(settings: settings)
                }
            }
        }
    }
}
