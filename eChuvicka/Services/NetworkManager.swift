import Foundation
import Network

public enum ConnectionMode: Sendable, Equatable {
    case disconnected
    case searching
    /// Infrastructure Wi‑Fi (router, hotspot, sdílená síť) — not AWDL peer-to-peer.
    case connectedLocalNetwork
    case connectedDirect

    public var localizedTitle: String {
        switch self {
        case .disconnected: L10n.Connection.disconnected
        case .searching: L10n.Connection.searching
        case .connectedLocalNetwork: L10n.Connection.wifi
        case .connectedDirect: L10n.Connection.p2p
        }
    }
}

/// Discovered child unit. `id` is a stable installation UUID (not the pairing PIN).
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: String
    public let pairingPIN: String
    public let name: String
    public let displayName: String
    public let requiresPin: Bool
    public let endpoint: NWEndpoint
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
            && lhs.pairingPIN == rhs.pairingPIN
            && lhs.requiresPin == rhs.requiresPin
            && lhs.displayName == rhs.displayName
    }
}

public struct DeviceInfoPacket: Codable, Sendable {
    public let deviceName: String
    public let deviceId: String

    public init(deviceName: String, deviceId: String = "") {
        self.deviceName = deviceName
        self.deviceId = deviceId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
    }
}

public struct SettingsPacket: Codable, Sendable {
    public let isVOXEnabled: Bool
    public let voxSensitivity: Double
    public let voxHoldTime: Double
    public let isPinRequired: Bool
    
    public init(
        isVOXEnabled: Bool,
        voxSensitivity: Double,
        voxHoldTime: Double,
        isPinRequired: Bool
    ) {
        self.isVOXEnabled = isVOXEnabled
        self.voxSensitivity = voxSensitivity
        self.voxHoldTime = voxHoldTime
        self.isPinRequired = isPinRequired
    }
}

public struct AuthRequestPacket: Codable, Sendable {
    public let pin: String
    public let clientDeviceId: String
    
    public init(pin: String, clientDeviceId: String) {
        self.pin = pin
        self.clientDeviceId = clientDeviceId
    }
}

public struct AuthResponsePacket: Codable, Sendable {
    public let ok: Bool
    public let deviceId: String
    public let deviceName: String
    public let message: String?
    
    public init(ok: Bool, deviceId: String, deviceName: String, message: String? = nil) {
        self.ok = ok
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.message = message
    }
}

@MainActor
public class NetworkManager: ObservableObject {
    @Published public var connectionMode: ConnectionMode = .disconnected
    /// True only after successful auth handshake.
    @Published public var isConnected: Bool = false
    @Published public var generatedPIN: String = ""
    @Published public var peerBatteryLevel: Float = 1.0
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var connectedDeviceName: String?
    @Published public var connectedDeviceId: String?
    @Published public var lastAuthError: String?
    /// Soft status while recovering after Wi‑Fi/hotspot → P2P path change (not a hard failure).
    @Published public var reconnectHint: String?
    
    public var onAudioDataReceived: (@Sendable (Data) -> Void)?
    public var onHeartbeatReceived: (@Sendable (HeartbeatPacket) -> Void)?
    public var onSettingsReceived: (@Sendable (SettingsPacket) -> Void)?
    public var onAuthenticated: (@Sendable (_ peerDeviceId: String, _ peerName: String) -> Void)?
    /// Fired when the system network path changes (hotspot off, Wi‑Fi switch, etc.).
    public var onNetworkPathChanged: (@Sendable (_ isSatisfied: Bool) -> Void)?
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var lastPathSignature: String = ""
    private var childHostRestartTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    
    private let serviceType = "_echuvicka._tcp"
    private let maxPayloadLength: UInt32 = 256_000
    private let connectTimeoutSeconds: TimeInterval = 12
    
    private var hostedPairingPart = ""
    private var hostedDeviceId = ""
    private var hostedPIN = ""
    private var hostedRequiresPin = true
    private var localRole: AppRole = .none
    private var localDeviceId = ""
    private var localDisplayName = ""
    private var pendingAuthPIN = ""
    private var isAuthenticated = false
    
    /// TCP/auth handshake in progress (not yet fully connected).
    public var isConnectionInProgress: Bool {
        connection != nil && !isConnected
    }
    
    public init() {
        startPathMonitor()
    }
    
    private func makeTCPParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 5
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        // Prefer whichever interface works after hotspot → AWDL transitions.
        params.serviceClass = .responsiveData
        return params
    }
    
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleSystemPathUpdate(path)
            }
        }
        monitor.start(queue: .main)
    }
    
    private func pathSignature(_ path: NWPath) -> String {
        var parts: [String] = [String(describing: path.status)]
        if path.usesInterfaceType(.wifi) { parts.append("wifi") }
        if path.usesInterfaceType(.other) { parts.append("other") }
        if path.usesInterfaceType(.cellular) { parts.append("cell") }
        if path.usesInterfaceType(.wiredEthernet) { parts.append("eth") }
        return parts.joined(separator: "|")
    }
    
    private func handleSystemPathUpdate(_ path: NWPath) {
        let signature = pathSignature(path)
        let statusChanged = lastPathStatus != path.status
        let previousSignature = lastPathSignature
        let interfacesChanged = previousSignature != signature && !previousSignature.isEmpty
        let previousStatus = lastPathStatus
        lastPathStatus = path.status
        lastPathSignature = signature
        
        guard statusChanged || interfacesChanged else { return }
        print("[Network] Path changed: \(signature)")
        
        // Mac without a router often stays `.unsatisfied` even while AWDL/P2P works.
        // Never kill an in-progress handshake for that — it was blocking Connect taps.
        // Only drop an *authenticated* session when we clearly left infrastructure Wi‑Fi
        // (e.g. hotspot turned off) or lost the previous wifi path entirely.
        if isAuthenticated && isConnected {
            let leftHotspotOrRouter =
                previousStatus == .satisfied
                && path.status != .satisfied
                && previousSignature.contains("wifi")
            let lostWifiWithoutAWDL =
                previousSignature.contains("wifi")
                && !signature.contains("wifi")
                && !signature.contains("other")
            if leftHotspotOrRouter || lostWifiWithoutAWDL {
                print("[Network] Dropping authenticated link after infrastructure path loss")
                lastAuthError = nil
                reconnectHint = L10n.Hint.networkChangedRestore
                handleDisconnect()
            }
        }
        
        // Child: recreate listener after interface change, debounced (don't flap during P2P).
        if localRole == .child, !hostedDeviceId.isEmpty, !hostedPIN.isEmpty, interfacesChanged {
            childHostRestartTask?.cancel()
            childHostRestartTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                guard self.localRole == .child, !self.isAuthenticated else { return }
                print("[Child] Restarting Bonjour listener after path change")
                self.restartHostingPreservingIdentity()
            }
        }
        
        onNetworkPathChanged?(path.status == .satisfied)
    }
    
    // MARK: - Child / Transmitter
    
    private func advertisedInstanceName() -> String {
        let budget = 63 - hostedPairingPart.utf8.count - DeviceName.serviceSeparator.utf8.count
        let label = DeviceName.labelForService(availableBytes: max(0, budget), role: .child)
        return label.isEmpty
            ? hostedPairingPart
            : "\(hostedPairingPart)\(DeviceName.serviceSeparator)\(label)"
    }
    
    private func makeAdvertisedService() -> NWListener.Service {
        let instanceName = advertisedInstanceName()
        return NWListener.Service(
            name: instanceName,
            type: serviceType,
            txtRecord: NWTXTRecord([
                "deviceName": DeviceName.current(for: .child),
                "deviceId": hostedDeviceId
            ])
        )
    }
    
    public func refreshAdvertisedDeviceName() {
        guard let listener = listener, !hostedPairingPart.isEmpty else { return }
        listener.service = makeAdvertisedService()
        #if DEBUG
        print("[Child] Re-advertising as \(advertisedInstanceName())")
        #endif
    }
    
    public func updatePinRequirement(_ isPinRequired: Bool) {
        guard listener != nil, !hostedPairingPart.isEmpty else { return }
        
        hostedRequiresPin = isPinRequired
        let pin = hostedPIN.isEmpty ? (hostedPairingPart.components(separatedBy: "-").last ?? generatedPIN) : hostedPIN
        let newPrefix = isPinRequired ? "eChuvicka-PIN-" : "eChuvicka-OPEN-"
        let newPairingPart = newPrefix + pin
        guard newPairingPart != hostedPairingPart else { return }
        
        hostedPairingPart = newPairingPart
        hostedPIN = pin
        if isPinRequired {
            generatedPIN = pin
        }
        listener?.service = makeAdvertisedService()
        #if DEBUG
        print("[Child] PIN requirement updated, advertising as \(advertisedInstanceName())")
        #endif
    }
    
    public func startHosting(isPinRequired: Bool, deviceId: String, pairingPIN: String) {
        // Preserve path monitor; only tear down previous listener/browser/connection.
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        connection = nil
        isAuthenticated = false
        isConnected = false
        discoveredDevices = []
        connectedDeviceName = nil
        connectedDeviceId = nil
        hostedPairingPart = ""
        
        localRole = .child
        hostedDeviceId = deviceId
        hostedPIN = pairingPIN
        hostedRequiresPin = isPinRequired
        localDeviceId = deviceId
        localDisplayName = DeviceName.current(for: .child)
        generatedPIN = pairingPIN
        
        let params = makeTCPParameters()
        
        do {
            let nwListener = try NWListener(using: params)
            hostedPairingPart = (isPinRequired ? "eChuvicka-PIN-" : "eChuvicka-OPEN-") + pairingPIN
            nwListener.service = makeAdvertisedService()
            #if DEBUG
            print("[Child] Advertising as \(advertisedInstanceName()) id=\(deviceId)")
            #endif
            
            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.connectionMode = .searching
                        print("[Child] Listener ready, waiting for parent...")
                    case .failed(let error):
                        print("[Child] Listener failed: \(error)")
                        self.connectionMode = .disconnected
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
            }
            
            nwListener.newConnectionHandler = { [weak self] newConnection in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.isAuthenticated, self.connection != nil {
                        print("[Child] Rejecting extra parent connection")
                        newConnection.cancel()
                        return
                    }
                    print("[Child] Incoming parent TCP — awaiting auth")
                    self.setupConnection(newConnection, asParentClient: false)
                }
            }
            
            nwListener.start(queue: .main)
            listener = nwListener
            connectionMode = .searching
            
        } catch {
            print("[Child] Failed to start listener: \(error)")
        }
    }
    
    /// Recreate listener/Bonjour after Wi‑Fi/hotspot/AWDL change without changing PIN or device id.
    public func restartHostingPreservingIdentity() {
        guard localRole == .child, !hostedDeviceId.isEmpty, !hostedPIN.isEmpty else { return }
        let deviceId = hostedDeviceId
        let pin = hostedPIN
        let requiresPin = hostedRequiresPin
        
        // Tear down only listener + peer link; keep role / identity.
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        connection = nil
        isAuthenticated = false
        isConnected = false
        
        listener?.cancel()
        listener = nil
        
        startHosting(isPinRequired: requiresPin, deviceId: deviceId, pairingPIN: pin)
    }
    
    // MARK: - Parent / Receiver
    
    public func startBrowsing() {
        let keepRole = localRole
        stopBrowsingOnly()
        if !isConnected && !isConnectionInProgress {
            if let conn = connection {
                conn.stateUpdateHandler = nil
                conn.cancel()
            }
            connection = nil
            isAuthenticated = false
        }
        
        localRole = keepRole == .none ? .parent : keepRole
        beginBrowser()
    }
    
    /// Fresh Bonjour browse without killing a connection attempt mid-flight.
    public func restartBrowserPreservingConnectionAttempt() {
        guard localRole == .parent else {
            startBrowsing()
            return
        }
        stopBrowsingOnly()
        beginBrowser()
    }
    
    private func stopBrowsingOnly() {
        browser?.cancel()
        browser = nil
        discoveredDevices = []
    }
    
    private func beginBrowser() {
        let params = makeTCPParameters()
        let nwBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        
        nwBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectionMode = .searching
                    print("[Parent] Browser ready, searching for children...")
                case .failed(let error):
                    print("[Parent] Browser failed: \(error)")
                    if !self.isConnected {
                        self.connectionMode = .disconnected
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        
        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self = self else { return }
                var devices: [DiscoveredDevice] = []
                
                for result in results {
                    guard case let .service(name, _, _, _) = result.endpoint else { continue }
                    
                    let requiresPin = name.contains("-PIN-")
                    let pairingPIN = DeviceName.pairingPIN(fromServiceInstanceName: name)
                    
                    var txtName: String?
                    var txtDeviceId: String?
                    if case .bonjour(let txtRecord) = result.metadata {
                        txtName = txtRecord["deviceName"]
                        txtDeviceId = txtRecord["deviceId"]
                    }
                    
                    let stableId: String
                    if let txtDeviceId, !txtDeviceId.isEmpty {
                        stableId = txtDeviceId
                    } else {
                        stableId = "pin:\(pairingPIN)"
                    }
                    let displayName = DeviceName.displayName(
                        fromServiceInstanceName: name,
                        txtDeviceName: txtName
                    )
                    
                    devices.append(DiscoveredDevice(
                        id: stableId,
                        pairingPIN: pairingPIN,
                        name: name,
                        displayName: displayName,
                        requiresPin: requiresPin,
                        endpoint: result.endpoint
                    ))
                }
                
                self.discoveredDevices = devices
                print("[Parent] Found \(devices.count) device(s): \(devices.map(\.displayName))")
            }
        }
        
        nwBrowser.start(queue: .main)
        browser = nwBrowser
        if !isConnected {
            connectionMode = .searching
        }
        localRole = .parent
    }
    
    public func connectToDevice(
        _ device: DiscoveredDevice,
        authPIN: String,
        localDeviceId: String,
        localDeviceName: String
    ) {
        connectedDeviceName = device.displayName
        connectedDeviceId = device.id
        pendingAuthPIN = authPIN
        self.localDeviceId = localDeviceId
        self.localDisplayName = localDeviceName
        localRole = .parent
        lastAuthError = nil
        reconnectHint = L10n.Hint.connecting(to: device.displayName)
        #if DEBUG
        print("[Parent] Connecting to \(device.displayName) id=\(device.id) service=\(device.name)")
        #endif
        
        let params = makeTCPParameters()
        // Always resolve by Bonjour service name so we don't reuse a dead hotspot endpoint.
        let endpoint = NWEndpoint.service(
            name: device.name,
            type: serviceType,
            domain: "local.",
            interface: nil
        )
        let newConnection = NWConnection(to: endpoint, using: params)
        
        // Keep browsing until auth succeeds — cancelling Bonjour early breaks some P2P paths on macOS.
        setupConnection(newConnection, asParentClient: true)
        startConnectTimeout()
    }
    
    private func startConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(connectTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard isConnectionInProgress, !isAuthenticated else { return }
            print("[Parent] Connect timed out after \(Int(connectTimeoutSeconds))s")
            lastAuthError = nil
            reconnectHint = L10n.Hint.connectTimeout
            if let conn = connection {
                conn.stateUpdateHandler = nil
                conn.cancel()
            }
            handleDisconnect()
            // Resume discovery so the user can tap again / auto-reconnect can retry.
            if localRole == .parent {
                restartBrowserPreservingConnectionAttempt()
            }
        }
    }
    
    private func cancelConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
    }
    
    // MARK: - Connection Setup
    
    private func setupConnection(_ newConnection: NWConnection, asParentClient: Bool) {
        if let old = connection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        connection = newConnection
        isAuthenticated = false
        isConnected = false
        
        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .preparing:
                    print("[Connection] Preparing...")
                case .ready:
                    print("[Connection] TCP ready — starting auth")
                    self.cancelConnectTimeout()
                    self.updateConnectionMode(from: newConnection.currentPath)
                    self.startReceiving()
                    if asParentClient {
                        self.sendAuthRequest()
                    }
                case .failed(let error):
                    print("[Connection] Failed: \(error)")
                    self.cancelConnectTimeout()
                    self.applyConnectionFailure(error)
                    self.handleDisconnect()
                    if self.localRole == .parent {
                        self.restartBrowserPreservingConnectionAttempt()
                    }
                case .waiting(let error):
                    print("[Connection] Waiting: \(error)")
                    // Transient — e.g. after hotspot off before AWDL is up.
                    self.lastAuthError = nil
                    self.reconnectHint = L10n.Hint.waitingP2P
                case .cancelled:
                    print("[Connection] Cancelled")
                    self.cancelConnectTimeout()
                    self.handleDisconnect()
                default:
                    break
                }
            }
        }
        
        newConnection.pathUpdateHandler = { [weak self] newPath in
            Task { @MainActor in
                guard let self = self, self.connection != nil else { return }
                self.updateConnectionMode(from: newPath)
            }
        }
        
        newConnection.start(queue: .main)
    }
    
    private func sendAuthRequest() {
        let packet = AuthRequestPacket(pin: pendingAuthPIN, clientDeviceId: localDeviceId)
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x05, payload: data, requireAuth: false)
    }
    
    private func handleAuthRequest(_ packet: AuthRequestPacket) {
        guard localRole == .child else { return }
        
        let pinOK: Bool
        if hostedRequiresPin {
            pinOK = packet.pin == hostedPIN
        } else {
            pinOK = true
        }
        
        let response = AuthResponsePacket(
            ok: pinOK,
            deviceId: hostedDeviceId,
            deviceName: DeviceName.current(for: .child),
            message: pinOK ? nil : "invalid_pin"
        )
        if let data = try? JSONEncoder().encode(response) {
            sendFramedMessage(type: 0x06, payload: data, requireAuth: false)
        }
        
        if pinOK {
            markAuthenticated(peerDeviceId: packet.clientDeviceId, peerName: L10n.Device.parentDefault)
            sendDeviceInfo()
        } else {
            print("[Child] Auth rejected")
            connection?.cancel()
            handleDisconnect()
        }
    }
    
    private func handleAuthResponse(_ packet: AuthResponsePacket) {
        guard localRole == .parent else { return }
        if packet.ok {
            connectedDeviceId = packet.deviceId
            connectedDeviceName = packet.deviceName
            markAuthenticated(peerDeviceId: packet.deviceId, peerName: packet.deviceName)
            sendDeviceInfo()
        } else {
            lastAuthError = L10n.Auth.message(fromNetwork: packet.message)
            print("[Parent] Auth failed: \(lastAuthError ?? "")")
            connection?.cancel()
            handleDisconnect()
        }
    }
    
    private func markAuthenticated(peerDeviceId: String, peerName: String) {
        cancelConnectTimeout()
        isAuthenticated = true
        isConnected = true
        reconnectHint = nil
        lastAuthError = nil
        connectedDeviceId = peerDeviceId.isEmpty ? connectedDeviceId : peerDeviceId
        if !peerName.isEmpty {
            connectedDeviceName = peerName
        }
        // Stop browsing once linked to save energy.
        browser?.cancel()
        browser = nil
        onAuthenticated?(connectedDeviceId ?? peerDeviceId, connectedDeviceName ?? peerName)
    }
    
    private func handleDisconnect() {
        cancelConnectTimeout()
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.pathUpdateHandler = nil
            conn.cancel()
        }
        isAuthenticated = false
        isConnected = false
        connectionMode = .disconnected
        connectedDeviceName = nil
        connectedDeviceId = nil
        connection = nil
    }
    
    private func applyConnectionFailure(_ error: NWError) {
        if Self.isTransientNetworkError(error) {
            lastAuthError = nil
            reconnectHint = L10n.Hint.networkChangedRetry
            return
        }
        reconnectHint = nil
        lastAuthError = L10n.Hint.connectionFailed
    }
    
    /// Hotspot/Wi‑Fi teardown often surfaces as ENOTCONN (57) / POSIX / DNS failures.
    static func isTransientNetworkError(_ error: NWError) -> Bool {
        switch error {
        case .posix(let code):
            switch code {
            case .ENOTCONN, .ENETDOWN, .ENETUNREACH, .EHOSTUNREACH, .ECONNRESET, .EPIPE, .ETIMEDOUT, .ECONNABORTED:
                return true
            default:
                return false
            }
        case .dns:
            return true
        default:
            let text = error.localizedDescription.lowercased()
            return text.contains("not connected")
                || text.contains("socket")
                || text.contains("network is down")
                || text.contains("57")
        }
    }
    
    private func updateConnectionMode(from path: NWPath?) {
        guard let path else {
            connectionMode = .connectedDirect
            return
        }
        
        if path.usesInterfaceType(.other) {
            connectionMode = .connectedDirect
            return
        }
        
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            connectionMode = .connectedLocalNetwork
            return
        }
        
        connectionMode = .connectedDirect
    }
    
    public func clearConnectionErrors() {
        lastAuthError = nil
        reconnectHint = nil
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        hostedPairingPart = ""
        
        browser?.cancel()
        browser = nil
        
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.pathUpdateHandler = nil
            conn.cancel()
        }
        connection = nil
        
        cancelConnectTimeout()
        childHostRestartTask?.cancel()
        childHostRestartTask = nil
        
        isAuthenticated = false
        isConnected = false
        connectionMode = .disconnected
        discoveredDevices = []
        connectedDeviceName = nil
        connectedDeviceId = nil
        lastAuthError = nil
        reconnectHint = nil
        localRole = .none
    }
    
    // MARK: - Data Transfer
    
    public func sendAudioData(_ data: Data) {
        sendFramedMessage(type: 0x01, payload: data, requireAuth: true)
    }
    
    public func sendHeartbeat(_ packet: HeartbeatPacket) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x02, payload: data, requireAuth: true)
    }
    
    public func sendSettings(_ packet: SettingsPacket) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x03, payload: data, requireAuth: true)
    }
    
    public func sendDeviceInfo() {
        let roleForName: AppRole = (localRole == .parent) ? .parent : .child
        let packet = DeviceInfoPacket(
            deviceName: DeviceName.current(for: roleForName),
            deviceId: localDeviceId.isEmpty ? hostedDeviceId : localDeviceId
        )
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x04, payload: data, requireAuth: true)
    }
    
    private func sendFramedMessage(type: UInt8, payload: Data, requireAuth: Bool) {
        guard let connection = connection else { return }
        if requireAuth && !isAuthenticated { return }
        guard payload.count <= Int(maxPayloadLength) else {
            print("[Send] Payload too large (\(payload.count)) — dropped")
            return
        }
        
        var message = Data()
        message.append(type)
        var length = UInt32(payload.count).bigEndian
        message.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        message.append(payload)
        
        connection.send(content: message, completion: .contentProcessed({ error in
            if let error = error {
                print("[Send] Error: \(error)")
            }
        }))
    }
    
    // MARK: - Receive
    
    private static func u32BigEndian(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        }
    }
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] headerData, _, isComplete, error in
            if let error = error {
                #if DEBUG
                print("[Receive] Header error: \(error)")
                #endif
                Task { @MainActor in self?.handleDisconnect() }
                return
            }
            
            guard let headerData = headerData, headerData.count == 5 else {
                if isComplete {
                    Task { @MainActor in self?.handleDisconnect() }
                } else {
                    Task { @MainActor in self?.startReceiving() }
                }
                return
            }
            
            let type = headerData[0]
            let length = Self.u32BigEndian(headerData.subdata(in: 1..<5))
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if length == 0 || length > self.maxPayloadLength {
                    #if DEBUG
                    print("[Receive] Invalid payload length \(length) — disconnect")
                    #endif
                    self.handleDisconnect()
                    return
                }
                
                connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payloadData, _, payloadComplete, error2 in
                    if let error2 = error2 {
                        #if DEBUG
                        print("[Receive] Payload error: \(error2)")
                        #endif
                        Task { @MainActor in self?.handleDisconnect() }
                        return
                    }
                    
                    Task { @MainActor [weak self] in
                        if let payloadData = payloadData {
                            self?.dispatchPayload(type: type, data: payloadData)
                        }
                        if payloadComplete {
                            self?.handleDisconnect()
                        } else {
                            self?.startReceiving()
                        }
                    }
                }
            }
        }
    }
    
    private func dispatchPayload(type: UInt8, data: Data) {
        switch type {
        case 0x05:
            if let packet = try? JSONDecoder().decode(AuthRequestPacket.self, from: data) {
                handleAuthRequest(packet)
            }
        case 0x06:
            if let packet = try? JSONDecoder().decode(AuthResponsePacket.self, from: data) {
                handleAuthResponse(packet)
            }
        case 0x01:
            guard isAuthenticated else { return }
            onAudioDataReceived?(data)
        case 0x02:
            guard isAuthenticated else { return }
            if let packet = try? JSONDecoder().decode(HeartbeatPacket.self, from: data) {
                onHeartbeatReceived?(packet)
                peerBatteryLevel = packet.batteryLevel
            }
        case 0x03:
            guard isAuthenticated else { return }
            if let packet = try? JSONDecoder().decode(SettingsPacket.self, from: data) {
                onSettingsReceived?(packet)
            }
        case 0x04:
            guard isAuthenticated else { return }
            if let packet = try? JSONDecoder().decode(DeviceInfoPacket.self, from: data),
               !packet.deviceName.isEmpty {
                connectedDeviceName = packet.deviceName
                if !packet.deviceId.isEmpty {
                    connectedDeviceId = packet.deviceId
                }
                print("[Connection] Peer device name: \(packet.deviceName)")
            }
        default:
            break
        }
    }
}
