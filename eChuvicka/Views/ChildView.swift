import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ChildView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        coordinator.stop()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(L10n.Common.back)
                        }
                        .font(.system(.body, design: .rounded, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.indigo)
                    
                    Spacer()
                    
                    Text(resolvedDeviceName)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    
                    Spacer()
                    
                    NavigationLink {
                        SettingsView(
                            role: .child,
                            onCommitDeviceName: { coordinator.applyDeviceNameChange() },
                            onPinRequirementChange: { coordinator.applyPinRequirementChange() }
                        )
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(.body, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.indigo)
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
                                Text(L10n.Child.pairingPin)
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
                                Text(L10n.Child.openConnection)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Status Badge
                        ConnectionStatusBadge(
                            mode: coordinator.connectionMode,
                            latencyMs: coordinator.latencyMs,
                            wifiRSSIDbm: coordinator.wifiRSSIDbm
                        )
                        
                        // Audio Visualizer
                        ZStack {
                            AudioLevelView(audioLevel: coordinator.audioLevel, isCapturing: coordinator.isConnected, isTransmitting: coordinator.audioManager.isTransmitting)
                                .frame(height: 200)
                        }
                        
                        // Status Text
                        VStack(spacing: 8) {
                            if coordinator.isConnected {
                                if coordinator.audioManager.isTransmitting {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 12, height: 12)
                                        Text(L10n.Child.transmitting)
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                            .foregroundColor(.orange)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 10, height: 10)
                                        Text(L10n.Child.micOn)
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                if coordinator.isParentSpeaking {
                                    Text(L10n.Child.parentSpeaking)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.top, 4)
                                }
                            } else {
                                Text(L10n.Child.waiting)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundColor(.secondary)
                                Text(L10n.Child.needSecondDevice)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                        }
                        
                        #if os(iOS)
                        Text(L10n.Child.lockHint)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(coordinator.audioManager.$audioLevel) { _ in }
        .onReceive(coordinator.audioManager.$isTransmitting) { _ in }
        #if os(iOS)
        .onAppear {
            ScreenSleepPolicy.allowSystemAutoLock()
        }
        #endif
    }
    
    private var resolvedDeviceName: String {
        let custom = settings.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? DeviceName.defaultName(for: .child) : custom
    }
}
