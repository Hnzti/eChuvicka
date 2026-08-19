import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ParentView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @EnvironmentObject var settings: AppSettings
    @State private var isPressingPTT = false
    
    // For PIN entry
    @State private var selectedDevice: DiscoveredDevice? = nil
    @State private var pin: String = ""
    @State private var showPinError = false
    
    var body: some View {
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
                .foregroundColor(.teal)
                
                Spacer()
                
                Text(resolvedDeviceName)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                
                Spacer()
                
                NavigationLink {
                    SettingsView(
                        role: .parent,
                        onCommitDeviceName: { coordinator.applyDeviceNameChange() }
                    )
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(.body, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.teal)
            }
            .layoutPriority(1)
            .padding()
            #if os(iOS)
            .background(Color.black.opacity(0.05).ignoresSafeArea(edges: .top))
            #else
            .background(Color.black.opacity(0.05))
            #endif
            
            if !coordinator.isConnected {
                if let device = selectedDevice {
                    // PIN Entry Screen
                    VStack(spacing: 30) {
                        HStack {
                            Button(action: {
                                selectedDevice = nil
                                pin = ""
                                showPinError = false
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text(L10n.Parent.backToList)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.teal)
                            
                            Spacer()
                        }
                        
                        Spacer()
                        
                        Text(L10n.Parent.enterPin(device.displayName))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        
                        PINEntryView(pin: $pin)
                            .onChange(of: pin) { _, newPin in
                                if newPin.count < 4 {
                                    showPinError = false
                                    return
                                }
                                if newPin == device.pairingPIN {
                                    showPinError = false
                                    coordinator.connectToDevice(device, authPIN: newPin)
                                    selectedDevice = nil
                                    pin = ""
                                } else {
                                    showPinError = true
                                    #if os(iOS)
                                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                                    #endif
                                    DispatchQueue.main.async {
                                        pin = ""
                                    }
                                }
                            }
                        
                        if showPinError {
                            Text(L10n.Parent.wrongPin)
                                .foregroundColor(.red)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .transition(.opacity)
                        }
                        
                        if let authError = coordinator.lastAuthError {
                            Text(authError)
                                .foregroundColor(.red)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                        }
                        
                        Spacer()
                    }
                    .padding()
                } else {
                    // Device Discovery Screen
                    VStack(spacing: 20) {
                        Spacer().frame(height: 20)
                        
                        Text(L10n.Parent.selectChild)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        
                        if let authError = coordinator.lastAuthError {
                            Text(authError)
                                .foregroundColor(.red)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .padding(.horizontal)
                        } else if let hint = coordinator.networkManager.reconnectHint {
                            Text(hint)
                                .foregroundColor(.teal)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        if coordinator.discoveredDevices.isEmpty {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                if coordinator.isAwaitingDropReconnect {
                                    Text(L10n.Parent.reconnecting)
                                        .foregroundColor(.teal)
                                        .font(.headline)
                                    Text(L10n.Parent.p2pHint)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                } else {
                                    Text(L10n.Common.searching)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    if coordinator.isAwaitingDropReconnect {
                                        Text(L10n.Parent.restoringLast)
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                            .foregroundColor(.teal)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal)
                                    }
                                    
                                    ForEach(coordinator.discoveredDevices, id: \.id) { device in
                                        Button(action: {
                                            let skipPin = !device.requiresPin || coordinator.canSkipPin(for: device)
                                            if skipPin {
                                                coordinator.connectToDevice(device)
                                            } else {
                                                selectedDevice = device
                                                pin = ""
                                                showPinError = false
                                            }
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(device.displayName)
                                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                                    if coordinator.networkManager.isConnectionInProgress,
                                                       coordinator.networkManager.connectedDeviceId == device.id {
                                                        Text(L10n.Common.connecting)
                                                            .font(.system(.subheadline, design: .rounded))
                                                            .foregroundColor(.teal)
                                                    } else if !device.requiresPin {
                                                        Text(L10n.Parent.tapDirect)
                                                            .font(.system(.subheadline, design: .rounded))
                                                            .foregroundColor(.secondary)
                                                    } else if coordinator.canSkipPin(for: device) {
                                                        Text(L10n.Parent.trusted24h)
                                                            .font(.system(.subheadline, design: .rounded))
                                                            .foregroundColor(.secondary)
                                                    } else {
                                                        Text(L10n.Parent.tapPin)
                                                            .font(.system(.subheadline, design: .rounded))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: device.requiresPin
                                                      ? (coordinator.canSkipPin(for: device) ? "lock.open.fill" : "lock.fill")
                                                      : "lock.open.fill")
                                                    .foregroundColor(device.requiresPin && !coordinator.canSkipPin(for: device) ? .teal : .green)
                                            }
                                            .padding()
                                            .background(Color.secondary.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            } else {
                // Connected Monitoring Screen
                VStack(spacing: 16) {
                    if !coordinator.isConnectionAlive && coordinator.appSettings.isDisconnectAlarmEnabled {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(L10n.Parent.lostBang)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if !coordinator.isConnectionAlive {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(L10n.Parent.lost)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if coordinator.appSettings.isLowBatteryAlertEnabled
                                && coordinator.peerBatteryLevel <= Float(coordinator.appSettings.lowBatteryThreshold) {
                        HStack {
                            Image(systemName: "battery.25")
                            Text(L10n.Parent.lowBattery)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    ConnectionStatusBadge(
                        mode: coordinator.connectionMode,
                        latencyMs: coordinator.latencyMs,
                        wifiRSSIDbm: coordinator.wifiRSSIDbm
                    )
                    .padding(.top, 20)
                    
                    if let deviceName = coordinator.connectedDeviceName {
                        Text(deviceName)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Audio Visualizer
                    AudioLevelView(
                        audioLevel: coordinator.audioLevel,
                        isCapturing: coordinator.isConnectionAlive,
                        isTransmitting: coordinator.audioManager.isReceiving || isPressingPTT
                    )
                    .frame(minHeight: 100, idealHeight: 250, maxHeight: 300)
                    
                    // Status — mirror of child, from the parent's perspective
                    VStack(spacing: 8) {
                        if coordinator.isConnectionAlive {
                            if isPressingPTT {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.teal)
                                        .frame(width: 12, height: 12)
                                    Text(L10n.Parent.speaking)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                        .foregroundColor(.teal)
                                }
                            } else if coordinator.audioManager.isReceiving {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 12, height: 12)
                                    Text(L10n.Parent.receiving)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 10, height: 10)
                                    Text(L10n.Parent.listening)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }
                        } else if coordinator.isConnected {
                            Text(L10n.Parent.restoring)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    
                    // Child Battery
                    HStack(spacing: 8) {
                        Image(systemName: batteryIcon(for: coordinator.peerBatteryLevel))
                            .foregroundColor(batteryColor(for: coordinator.peerBatteryLevel))
                        Text(L10n.Parent.babyBattery(Int(coordinator.peerBatteryLevel * 100)))
                            .font(.system(.body, design: .rounded, weight: .medium))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                    
                    Spacer(minLength: 0)
                    
                    // PTT Button
                    VStack(spacing: 12) {
                        Text(L10n.Parent.holdToTalk)
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
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.default, value: coordinator.isConnected)
        .animation(.default, value: coordinator.isConnectionAlive)
        .animation(.default, value: selectedDevice)
        .onReceive(coordinator.audioManager.$audioLevel) { _ in }
        .onReceive(coordinator.audioManager.$isReceiving) { _ in }
        .onChange(of: coordinator.discoveredDevices) { _, devices in
            guard let selected = selectedDevice else { return }
            if let updated = devices.first(where: { $0.id == selected.id }) {
                selectedDevice = updated
                // Child turned PIN off — leave PIN screen, return to list (no auto-connect).
                if !updated.requiresPin {
                    pin = ""
                    showPinError = false
                    selectedDevice = nil
                }
            } else if !devices.contains(where: { $0.id == selected.id }) {
                selectedDevice = nil
                pin = ""
                showPinError = false
            }
        }
    }
    
    private var resolvedDeviceName: String {
        let custom = settings.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? DeviceName.defaultName(for: .parent) : custom
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

// Re-added PIN components
struct PINEntryView: View {
    @Binding var pin: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Hidden but focusable TextField that captures all input
            TextField("", text: $pin)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .foregroundColor(.clear)
                .accentColor(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: pin) { _, newValue in
                    var filtered = newValue.filter { $0.isNumber }
                    if filtered.count > 4 {
                        filtered = String(filtered.prefix(4))
                    }
                    if filtered != pin {
                        pin = filtered
                    }
                }
            
            // Visual PIN boxes
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    PINBox(
                        character: pin.count > index ? String(pin[pin.index(pin.startIndex, offsetBy: index)]) : "",
                        isActive: isFocused && pin.count == index
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
        }
        .frame(height: 70)
        .onAppear {
            // Auto-focus on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }
}

struct PINBox: View {
    let character: String
    let isActive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
            
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.teal : (character.isEmpty ? Color.clear : Color.teal.opacity(0.5)), lineWidth: 2)
            
            if !character.isEmpty {
                Text(character)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .transition(.scale.combined(with: .opacity))
            } else if isActive {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.teal)
                    .frame(width: 2, height: 24)
                    .opacity(isActive ? 1 : 0)
            }
        }
        .frame(width: 50, height: 60)
        .animation(.easeInOut(duration: 0.15), value: character)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}
