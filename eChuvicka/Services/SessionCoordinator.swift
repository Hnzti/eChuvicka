import Foundation
import Combine

@MainActor
public class SessionCoordinator: ObservableObject {
    @Published public var role: AppRole = .none
    
    public let networkManager = NetworkManager()
    public let audioManager = AudioManager()
    public let heartbeatMonitor = HeartbeatMonitor()
    public let appSettings = AppSettings()
    
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
        
        // Forward AudioManager state changes
        audioManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Forward HeartbeatMonitor state changes
        heartbeatMonitor.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Setup NetworkManager callbacks
        networkManager.onAudioDataReceived = { [weak self] data in
            Task { @MainActor in
                self?.heartbeatMonitor.dataReceived()
                self?.audioManager.playReceivedAudio(data)
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
                self.appSettings.isAutoNightModeEnabled = packet.isAutoNightModeEnabled
                self.appSettings.isPinRequired = packet.isPinRequired
                
                // Okamžitě restartovat záznam s novými hodnotami
                self.audioManager.startCapture(
                    voxEnabled: packet.isVOXEnabled,
                    voxThreshold: Float(packet.voxSensitivity),
                    voxHoldTime: packet.voxHoldTime
                ) { [weak self] data in
                    self?.networkManager.sendAudioData(data)
                    self?.heartbeatMonitor.dataReceived()
                }
                
                // Dětská UI obrazovka zareaguje na isAutoNightModeEnabled sama přes @AppStorage/EnvironmentObject
            }
        }
        
        // Setup Heartbeat callbacks
        heartbeatMonitor.onSendHeartbeat = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.audioManager.isTransmitting {
                    let packet = HeartbeatPacket(timestamp: Date(), batteryLevel: HeartbeatMonitor.currentBatteryLevel())
                    self.networkManager.sendHeartbeat(packet)
                }
            }
        }
        
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
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
            isAutoNightModeEnabled: appSettings.isAutoNightModeEnabled,
            isPinRequired: appSettings.isPinRequired
        )
        networkManager.sendSettings(packet)
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
        audioManager.isAudioBoostEnabled = appSettings.isAudioBoostEnabled
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
