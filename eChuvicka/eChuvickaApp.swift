import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct eChuvickaApp: App {
    @StateObject private var coordinator = SessionCoordinator()
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.appSettings)
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 600)
                #endif
                #if os(iOS)
                .onAppear {
                    ScreenSleepPolicy.allowSystemAutoLock()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        ScreenSleepPolicy.allowSystemAutoLock()
                    }
                }
                #endif
        }
    }
}

#if os(iOS)
enum ScreenSleepPolicy {
    /// App must never block Auto-Lock; locking is entirely up to iOS.
    static func allowSystemAutoLock() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
#endif

struct ContentView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    
    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.role {
                case .none:
                    RoleSelectionView()
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
        }
    }
}
