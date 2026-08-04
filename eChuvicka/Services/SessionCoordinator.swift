import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public class SessionCoordinator: ObservableObject {
    @Published public var role: AppRole = .none
    
    public let networkManager = NetworkManager()
    public let audioManager = AudioManager()
    public let heartbeatMonitor = HeartbeatMonitor()
    public let appSettings = AppSettings()
    
    @Published public var isParentSpeaking: Bool = false
    private var parentSpeakingTimer: Timer?
    private var deviceNameRefreshTask: Task<Void, Never>?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Convenience properties for Views
    
    public var connectionMode: ConnectionMode {
        networkManager.connectionMode
    }
    
    public var isConnected: Bool {
        networkManager.isConnected
    }
    
    public var audioLevel: Float {
        audioManager.audioLevel
    }
    
    public var isConnectionAlive: Bool {
        heartbeatMonitor.isConnectionAlive
    }
    
    public var peerBatteryLevel: Float {
        networkManager.peerBatteryLevel
    }
    
    public var latencyMs: Double {
        heartbeatMonitor.lastLatencyMs
    }
    
    public var generatedPIN: String {
        networkManager.generatedPIN
    }
    
    public var discoveredDevices: [DiscoveredDevice] {
        networkManager.discoveredDevices
    }
    
    public var connectedDeviceName: String? {
        networkManager.connectedDeviceName
    }
    
    public init() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        setupBindings()
    }
    
    private func setupBindings() {
        // Forward NetworkManager state changes
        networkManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // AudioManager publishes very frequently (every audio buffer). Views that need
        // levels must observe audioManager directly — forwarding here would rebuild
        // Parent/Child (and steal TextField focus in Settings) dozens of times per second.
        
        // Forward HeartbeatMonitor state changes
        heartbeatMonitor.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Setup NetworkManager callbacks
        networkManager.onAudioDataReceived = { [weak self] data in
            Task { @MainActor in
                guard let self = self else { return }
                self.heartbeatMonitor.dataReceived()
                self.audioManager.playReceivedAudio(data)
                
                if self.role == .child {
                    self.isParentSpeaking = true
                    self.parentSpeakingTimer?.invalidate()
                    self.parentSpeakingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                        Task { @MainActor in self?.isParentSpeaking = false }
                    }
                }
            }
        }
        
        networkManager.$discoveredDevices.sink { [weak self] devices in
            Task { @MainActor in
                guard let self = self, self.role == .parent, self.appSettings.isAutoReconnectEnabled else { return }
                let lastPIN = self.appSettings.lastConnectedPIN
                if !lastPIN.isEmpty, !self.isConnected, let target = devices.first(where: { $0.id == lastPIN }) {
                    print("Auto-reconnecting to \(lastPIN)")
                    self.connectToDevice(target)
                }
            }
        }.store(in: &cancellables)
        
        networkManager.$connectionMode.sink { [weak self] mode in
            Task { @MainActor in
                guard let self = self, self.role == .parent, self.appSettings.isAutoReconnectEnabled else { return }
                if mode == .disconnected, !self.appSettings.lastConnectedPIN.isEmpty {
                    // Try to browse again if disconnected
                    if self.networkManager.connectionMode == .disconnected {
                        self.networkManager.startBrowsing()
                    }
                }
            }
        }.store(in: &cancellables)
        
        networkManager.onHeartbeatReceived = { [weak self] packet in
            Task { @MainActor in
                self?.heartbeatMonitor.heartbeatReceived(packet)
            }
        }
        
        networkManager.onSettingsReceived = { [weak self] packet in
            Task { @MainActor in
                guard let self = self, self.role == .child else { return }
                
                print("[Child] Přijato nové nastavení od rodiče: VOX \(packet.isVOXEnabled), Citlivost \(packet.voxSensitivity)")
                
                // Uložit lokálně
                self.appSettings.isVOXEnabled = packet.isVOXEnabled
                self.appSettings.voxSensitivity = packet.voxSensitivity
                self.appSettings.voxHoldTime = packet.voxHoldTime
                self.appSettings.isPinRequired = packet.isPinRequired
                
                // Apply PIN/OPEN to the live Bonjour advertisement immediately.
                self.networkManager.updatePinRequirement(packet.isPinRequired)
                
                // Okamžitě restartovat záznam s novými hodnotami
                self.audioManager.startCapture(
                    voxEnabled: packet.isVOXEnabled,
                    voxThreshold: Float(packet.voxSensitivity),
                    voxHoldTime: packet.voxHoldTime
                ) { [weak self] data in
                    self?.networkManager.sendAudioData(data)
                    self?.heartbeatMonitor.dataReceived()
                }
            }
        }
        
        // Setup Heartbeat callbacks
        heartbeatMonitor.onSendHeartbeat = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let packet = HeartbeatPacket(timestamp: Date(), batteryLevel: HeartbeatMonitor.currentBatteryLevel())
                self.networkManager.sendHeartbeat(packet)
            }
        }
        
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.sendCurrentSettingsToChild()
                }
            }.store(in: &cancellables)
        
        networkManager.$isConnected.sink { [weak self] connected in
            Task { @MainActor in
                if connected {
                    self?.sendCurrentSettingsToChild()
                }
            }
        }.store(in: &cancellables)
    }
    
    public func sendCurrentSettingsToChild() {
        guard role == .parent, isConnected else { return }
        let packet = SettingsPacket(
            isVOXEnabled: appSettings.isVOXEnabled,
            voxSensitivity: appSettings.voxSensitivity,
            voxHoldTime: appSettings.voxHoldTime,
            isPinRequired: appSettings.isPinRequired
        )
        networkManager.sendSettings(packet)
    }
    
    public func applyDeviceNameChange() {
        // Don't call objectWillChange here — it rebuilds the settings screen and hides the text caret.
        deviceNameRefreshTask?.cancel()
        deviceNameRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard role == .child else { return }
            networkManager.refreshAdvertisedDeviceName()
            if isConnected {
                networkManager.sendDeviceInfo()
            }
        }
    }
    
    public func applyPinRequirementChange() {
        guard role == .child else { return }
        networkManager.updatePinRequirement(appSettings.isPinRequired)
    }
    
    public func startAsChild() {
        role = .child
        networkManager.startHosting(isPinRequired: appSettings.isPinRequired)
        audioManager.startCapture(
            voxEnabled: appSettings.isVOXEnabled,
            voxThreshold: Float(appSettings.voxSensitivity),
            voxHoldTime: appSettings.voxHoldTime
        ) { [weak self] data in
            self?.networkManager.sendAudioData(data)
            self?.heartbeatMonitor.dataReceived()
        }
        heartbeatMonitor.start(role: .child, alarmDelay: appSettings.disconnectAlarmDelay)
    }
    
    public func startBrowsingAsParent() {
        role = .parent
        networkManager.startBrowsing()
    }
    
    public func connectToDevice(_ device: DiscoveredDevice) {
        appSettings.lastConnectedPIN = device.id
        networkManager.connectToDevice(device)
        audioManager.preparePlayback()
        heartbeatMonitor.start(role: .parent, alarmDelay: appSettings.disconnectAlarmDelay)
    }
    
    public func startPTT() {
        guard role == .parent else { return }
        audioManager.startCapture(voxEnabled: false, voxThreshold: 0.0, voxHoldTime: 0.0) { [weak self] data in
            self?.networkManager.sendAudioData(data)
        }
    }
    
    public func stopPTT() {
        guard role == .parent else { return }
        audioManager.stopCapture()
    }
    
    public func stop() {
        role = .none
        networkManager.stop()
        audioManager.stopCapture()
        audioManager.stopPlayback()
        heartbeatMonitor.stop()
    }
}
