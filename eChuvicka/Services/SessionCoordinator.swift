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
    /// True only after an unexpected drop — allows auto-reconnect without PIN (within 24h).
    @Published public var isAwaitingDropReconnect: Bool = false
    private var parentSpeakingTimer: Timer?
    private var deviceNameRefreshTask: Task<Void, Never>?
    private var ignoreNextDisconnectForReconnect = false
    private var hadLiveConnection = false
    private var lastAppliedVOXSignature: String = ""
    private var reconnectTask: Task<Void, Never>?
    private var lastReconnectAttemptAt: Date = .distantPast
    private var reconnectCooldownSeconds: TimeInterval = 5
    /// Longer wait after hotspot/Wi‑Fi teardown so AWDL / Bonjour can come up.
    private let pathChangeReconnectDelay: TimeInterval = 10
    
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
    
    public var wifiRSSIDbm: Int? {
        heartbeatMonitor.wifiRSSIDbm
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
    
    public var lastAuthError: String? {
        networkManager.lastAuthError
    }
    
    public init() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        _ = appSettings.ensureStableDeviceId()
        setupBindings()
    }
    
    private func setupBindings() {
        networkManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        heartbeatMonitor.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        appSettings.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
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
        
        networkManager.onAuthenticated = { [weak self] peerDeviceId, _ in
            Task { @MainActor in
                guard let self = self, self.role == .parent else { return }
                self.networkManager.clearConnectionErrors()
                self.appSettings.rememberSuccessfulConnection(
                    deviceId: peerDeviceId,
                    pin: self.appSettings.lastConnectedPIN
                )
            }
        }
        
        networkManager.onNetworkPathChanged = { [weak self] isSatisfied in
            Task { @MainActor in
                guard let self = self, self.role == .parent else { return }
                guard self.appSettings.isAutoReconnectEnabled,
                      self.appSettings.isLastConnectionWithinTrustWindow else { return }
                
                // Infrastructure Wi‑Fi "unsatisfied" ≠ no D2D. AWDL can work with Wi‑Fi radio
                // on but not joined to a router/hotspot — never cancel reconnect for that.
                if self.hadLiveConnection || self.isAwaitingDropReconnect {
                    self.isAwaitingDropReconnect = true
                    self.networkManager.clearConnectionErrors()
                    self.networkManager.reconnectHint = isSatisfied
                        ? L10n.Hint.lookingWifiP2P
                        : L10n.Hint.lookingP2PNoRouter
                    self.startReconnectLoop(initialDelay: isSatisfied ? 2 : 3)
                }
            }
        }
        
        networkManager.$discoveredDevices.sink { [weak self] devices in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.role == .parent,
                      self.isAwaitingDropReconnect,
                      self.appSettings.isAutoReconnectEnabled,
                      self.appSettings.isLastConnectionWithinTrustWindow,
                      !self.isConnected,
                      !self.networkManager.isConnectionInProgress else { return }
                
                let now = Date()
                guard now.timeIntervalSince(self.lastReconnectAttemptAt) >= self.reconnectCooldownSeconds else { return }
                
                guard let target = self.resolveReconnectTarget(in: devices) else { return }
                
                self.lastReconnectAttemptAt = now
                self.networkManager.clearConnectionErrors()
                self.networkManager.reconnectHint = L10n.Hint.restoring
                print("Auto-reconnecting after drop to \(target.id)")
                self.connectToDevice(target, authPIN: self.appSettings.lastConnectedPIN)
            }
        }.store(in: &cancellables)
        
        networkManager.$isConnected.sink { [weak self] connected in
            Task { @MainActor in
                guard let self = self else { return }
                if connected {
                    self.ignoreNextDisconnectForReconnect = false
                    self.hadLiveConnection = true
                    self.isAwaitingDropReconnect = false
                    self.reconnectCooldownSeconds = 5
                    MonitorAlertPlayer.reset()
                    self.networkManager.clearConnectionErrors()
                    if self.role == .parent,
                       let deviceId = self.networkManager.connectedDeviceId,
                       !deviceId.isEmpty {
                        self.appSettings.rememberSuccessfulConnection(
                            deviceId: deviceId,
                            pin: self.appSettings.lastConnectedPIN
                        )
                    }
                    self.sendCurrentSettingsToChild()
                    return
                }
                
                guard self.role == .parent else { return }
                
                if self.ignoreNextDisconnectForReconnect {
                    self.ignoreNextDisconnectForReconnect = false
                    return
                }
                
                guard self.hadLiveConnection,
                      self.appSettings.isAutoReconnectEnabled,
                      self.appSettings.isLastConnectionWithinTrustWindow else {
                    self.isAwaitingDropReconnect = false
                    return
                }
                
                self.isAwaitingDropReconnect = true
                self.networkManager.clearConnectionErrors()
                self.networkManager.reconnectHint = L10n.Hint.interrupted
                self.startReconnectLoop(initialDelay: self.pathChangeReconnectDelay)
            }
        }.store(in: &cancellables)
        
        heartbeatMonitor.$isConnectionAlive.sink { [weak self] alive in
            Task { @MainActor in
                guard let self = self, self.role == .parent, self.isConnected else { return }
                if !alive {
                    MonitorAlertPlayer.playDisconnectAlarmIfNeeded(
                        enabled: self.appSettings.isDisconnectAlarmEnabled
                    )
                }
            }
        }.store(in: &cancellables)
        
        networkManager.$peerBatteryLevel.sink { [weak self] level in
            Task { @MainActor in
                guard let self = self, self.role == .parent, self.isConnected else { return }
                if level <= Float(self.appSettings.lowBatteryThreshold) {
                    MonitorAlertPlayer.playLowBatteryAlarmIfNeeded(
                        enabled: self.appSettings.isLowBatteryAlertEnabled
                    )
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
                
                print("[Child] Settings from parent: VOX \(packet.isVOXEnabled), sens \(packet.voxSensitivity)")
                
                self.appSettings.isVOXEnabled = packet.isVOXEnabled
                self.appSettings.voxSensitivity = packet.voxSensitivity
                self.appSettings.voxHoldTime = packet.voxHoldTime
                // PIN requirement is child-owned — never overwrite from parent packet.
                
                self.applyChildCaptureSettings(force: true)
            }
        }
        
        heartbeatMonitor.onSendHeartbeat = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let packet = HeartbeatPacket(timestamp: Date(), batteryLevel: HeartbeatMonitor.currentBatteryLevel())
                self.networkManager.sendHeartbeat(packet)
            }
        }
        
        // Debounced settings sync / live VOX apply (parent pushes; child applies locally).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.role == .parent {
                        self.sendCurrentSettingsToChild()
                    } else if self.role == .child {
                        self.heartbeatMonitor.updateAlarmDelay(self.appSettings.disconnectAlarmDelay)
                        self.applyChildCaptureSettings(force: false)
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
        deviceNameRefreshTask?.cancel()
        deviceNameRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            if role == .child {
                networkManager.refreshAdvertisedDeviceName()
            }
            if isConnected {
                networkManager.sendDeviceInfo()
            }
        }
    }
    
    public func applyPinRequirementChange() {
        guard role == .child else { return }
        networkManager.updatePinRequirement(appSettings.isPinRequired)
    }
    
    public func applyChildCaptureSettings(force: Bool) {
        guard role == .child else { return }
        let signature = "\(appSettings.isVOXEnabled)|\(appSettings.voxSensitivity)|\(appSettings.voxHoldTime)"
        guard force || signature != lastAppliedVOXSignature else { return }
        lastAppliedVOXSignature = signature
        
        audioManager.startCapture(
            voxEnabled: appSettings.isVOXEnabled,
            voxThreshold: Float(appSettings.voxSensitivity),
            voxHoldTime: appSettings.voxHoldTime
        ) { [weak self] data in
            self?.networkManager.sendAudioData(data)
            self?.heartbeatMonitor.dataReceived()
        }
    }
    
    public func startAsChild() {
        role = .child
        let deviceId = appSettings.ensureStableDeviceId()
        let pin = appSettings.currentOrCreateHostedPIN()
        networkManager.startHosting(
            isPinRequired: appSettings.isPinRequired,
            deviceId: deviceId,
            pairingPIN: pin
        )
        lastAppliedVOXSignature = ""
        applyChildCaptureSettings(force: true)
        heartbeatMonitor.start(role: .child, alarmDelay: appSettings.disconnectAlarmDelay)
    }
    
    public func startBrowsingAsParent() {
        role = .parent
        isAwaitingDropReconnect = false
        hadLiveConnection = false
        ignoreNextDisconnectForReconnect = false
        networkManager.lastAuthError = nil
        networkManager.startBrowsing()
    }
    
    public func connectToDevice(_ device: DiscoveredDevice, authPIN: String? = nil) {
        reconnectTask?.cancel()
        reconnectTask = nil
        ignoreNextDisconnectForReconnect = true
        isAwaitingDropReconnect = false
        networkManager.lastAuthError = nil
        
        let pinToUse: String
        if let authPIN {
            pinToUse = authPIN
        } else if !device.requiresPin {
            pinToUse = ""
        } else if canSkipPin(for: device) {
            pinToUse = appSettings.lastConnectedPIN
        } else {
            pinToUse = device.pairingPIN
        }
        
        // Remember intended PIN before auth completes (updated again on success).
        appSettings.lastConnectedPIN = pinToUse
        appSettings.lastConnectedDeviceId = device.id
        
        networkManager.connectToDevice(
            device,
            authPIN: pinToUse,
            localDeviceId: appSettings.ensureStableDeviceId(),
            localDeviceName: DeviceName.current(for: .parent)
        )
        audioManager.preparePlayback()
        heartbeatMonitor.start(role: .parent, alarmDelay: appSettings.disconnectAlarmDelay)
    }
    
    public func canSkipPin(for device: DiscoveredDevice) -> Bool {
        appSettings.canSkipPin(forDeviceId: device.id)
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
        ignoreNextDisconnectForReconnect = true
        isAwaitingDropReconnect = false
        hadLiveConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        role = .none
        lastAppliedVOXSignature = ""
        MonitorAlertPlayer.reset()
        networkManager.stop()
        audioManager.shutdown()
        heartbeatMonitor.stop()
        parentSpeakingTimer?.invalidate()
        parentSpeakingTimer = nil
    }
    
    /// Keep re-browsing until connected again (needed after Mac leaves iPhone hotspot → AWDL).
    private func startReconnectLoop(initialDelay: TimeInterval) {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            let firstWait = max(2, initialDelay)
            try? await Task.sleep(nanoseconds: UInt64(firstWait * 1_000_000_000))
            
            var attempt = 0
            while !Task.isCancelled {
                guard role == .parent, isAwaitingDropReconnect, !isConnected else { return }
                
                attempt += 1
                networkManager.clearConnectionErrors()
                networkManager.reconnectHint = attempt == 1
                    ? L10n.Hint.searchingBabyP2P
                    : L10n.Hint.attemptP2P(attempt)
                
                if networkManager.isConnectionInProgress {
                    // Let the current TCP attempt finish; refresh discovery only.
                    networkManager.restartBrowserPreservingConnectionAttempt()
                } else {
                    networkManager.startBrowsing()
                }
                
                // Wait for Bonjour + optional connect attempt before next round.
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }
    
    /// Prefer stable device id, then last PIN. Never fall back to “the only device on the LAN”.
    private func resolveReconnectTarget(in devices: [DiscoveredDevice]) -> DiscoveredDevice? {
        let lastId = appSettings.lastConnectedDeviceId
        if !lastId.isEmpty, let match = devices.first(where: { $0.id == lastId }) {
            return match
        }
        let lastPIN = appSettings.lastConnectedPIN
        if !lastPIN.isEmpty, let match = devices.first(where: { $0.pairingPIN == lastPIN }) {
            return match
        }
        return nil
    }
}
