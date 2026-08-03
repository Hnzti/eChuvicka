import Foundation
import Network

public enum ConnectionMode: String, Sendable {
    case disconnected = "Odpojeno"
    case searching = "Vyhledávání..."
    case connectedRouter = "Wi-Fi Router"
    case connectedDirect = "Přímé spojení (P2P)"
}

/// Represents a discovered child device
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: String  // PIN
    public let name: String
    public let displayName: String
    public let requiresPin: Bool
    public let endpoint: NWEndpoint
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(requiresPin)
        hasher.combine(displayName)
    }
    
    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id && lhs.requiresPin == rhs.requiresPin && lhs.displayName == rhs.displayName
    }
}

public struct DeviceInfoPacket: Codable, Sendable {
    public let deviceName: String

    public init(deviceName: String) {
        self.deviceName = deviceName
    }
}

public struct SettingsPacket: Codable, Sendable {
    public let isVOXEnabled: Bool
    public let voxSensitivity: Double
    public let voxHoldTime: Double
    public let isAutoNightModeEnabled: Bool
    public let displayOffDelay: Double
    public let isPinRequired: Bool
    
    public init(
        isVOXEnabled: Bool,
        voxSensitivity: Double,
        voxHoldTime: Double,
        isAutoNightModeEnabled: Bool,
        displayOffDelay: Double,
        isPinRequired: Bool
    ) {
        self.isVOXEnabled = isVOXEnabled
        self.voxSensitivity = voxSensitivity
        self.voxHoldTime = voxHoldTime
        self.isAutoNightModeEnabled = isAutoNightModeEnabled
        self.displayOffDelay = displayOffDelay
        self.isPinRequired = isPinRequired
    }
}

@MainActor
public class NetworkManager: ObservableObject {
    @Published public var connectionMode: ConnectionMode = .disconnected
    @Published public var isConnected: Bool = false
    @Published public var generatedPIN: String = ""
    @Published public var peerBatteryLevel: Float = 1.0
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var connectedDeviceName: String?
    
    public var onAudioDataReceived: (@Sendable (Data) -> Void)?
    public var onHeartbeatReceived: (@Sendable (HeartbeatPacket) -> Void)?
    public var onSettingsReceived: (@Sendable (SettingsPacket) -> Void)?
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    
    private let serviceType = "_echuvicka._tcp"
    private var hostedPairingPart = ""
    
    public init() {}
    
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
            txtRecord: NWTXTRecord(["deviceName": DeviceName.current(for: .child)])
        )
    }
    
    /// Re-publishes the Bonjour service after the user changes the device name.
    public func refreshAdvertisedDeviceName() {
        guard let listener = listener, !hostedPairingPart.isEmpty else { return }
        listener.service = makeAdvertisedService()
        print("[Child] Re-advertising as \(advertisedInstanceName())")
    }
    
    /// Switches PIN/OPEN in the live Bonjour name without regenerating the code.
    public func updatePinRequirement(_ isPinRequired: Bool) {
        guard listener != nil, !hostedPairingPart.isEmpty else { return }
        
        let pin = hostedPairingPart.components(separatedBy: "-").last ?? generatedPIN
        let newPrefix = isPinRequired ? "eChuvicka-PIN-" : "eChuvicka-OPEN-"
        let newPairingPart = newPrefix + pin
        guard newPairingPart != hostedPairingPart else { return }
        
        hostedPairingPart = newPairingPart
        if isPinRequired {
            generatedPIN = pin
        }
        listener?.service = makeAdvertisedService()
        print("[Child] PIN requirement updated, advertising as \(advertisedInstanceName())")
    }
    
    public func startHosting(isPinRequired: Bool) {
        stop()
        
        let pin = String(format: "%04d", Int.random(in: 0...9999))
        generatedPIN = pin
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        do {
            let nwListener = try NWListener(using: params)
            hostedPairingPart = (isPinRequired ? "eChuvicka-PIN-" : "eChuvicka-OPEN-") + pin
            nwListener.service = makeAdvertisedService()
            print("[Child] Advertising as \(advertisedInstanceName())")
            
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
                    print("[Child] Parent connected!")
                    self?.setupConnection(newConnection)
                }
            }
            
            nwListener.start(queue: .main)
            listener = nwListener
            connectionMode = .searching
            
        } catch {
            print("[Child] Failed to start listener: \(error)")
        }
    }
    
    // MARK: - Parent / Receiver
    
    public func startBrowsing() {
        stop()
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
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
                    self.connectionMode = .disconnected
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
                    let id = DeviceName.pairingPIN(fromServiceInstanceName: name)
                    
                    var txtName: String?
                    if case .bonjour(let txtRecord) = result.metadata {
                        txtName = txtRecord["deviceName"]
                    }
                    let displayName = DeviceName.displayName(
                        fromServiceInstanceName: name,
                        txtDeviceName: txtName
                    )
                    
                    devices.append(DiscoveredDevice(
                        id: id,
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
        connectionMode = .searching
    }
    
    public func connectToDevice(_ device: DiscoveredDevice) {
        connectedDeviceName = device.displayName
        print("[Parent] Connecting to device: \(device.displayName) (\(device.name))")
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        let newConnection = NWConnection(to: device.endpoint, using: params)
        
        browser?.cancel()
        browser = nil
        
        setupConnection(newConnection)
    }
    
    // MARK: - Connection Setup
    
    private func setupConnection(_ newConnection: NWConnection) {
        if let old = connection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        connection = newConnection
        
        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .preparing:
                    print("[Connection] Preparing...")
                case .ready:
                    print("[Connection] Ready!")
                    self.isConnected = true
                    self.connectionMode = .connectedRouter
                    self.startReceiving()
                    self.sendDeviceInfo()
                case .failed(let error):
                    print("[Connection] Failed: \(error)")
                    self.handleDisconnect()
                case .cancelled:
                    print("[Connection] Cancelled")
                    self.handleDisconnect()
                default:
                    break
                }
            }
        }
        
        newConnection.pathUpdateHandler = { [weak self] newPath in
            Task { @MainActor in
                guard let self = self, self.isConnected else { return }
                if newPath.usesInterfaceType(.wifi) {
                    self.connectionMode = .connectedRouter
                } else {
                    self.connectionMode = .connectedDirect
                }
            }
        }
        
        newConnection.start(queue: .main)
    }
    
    private func handleDisconnect() {
        isConnected = false
        connectionMode = .disconnected
        connectedDeviceName = nil
        connection = nil
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        hostedPairingPart = ""
        
        browser?.cancel()
        browser = nil
        
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        connection = nil
        
        isConnected = false
        connectionMode = .disconnected
        discoveredDevices = []
        connectedDeviceName = nil
    }
    
    // MARK: - Data Transfer
    
    public func sendAudioData(_ data: Data) {
        sendFramedMessage(type: 0x01, payload: data)
    }
    
    public func sendHeartbeat(_ packet: HeartbeatPacket) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x02, payload: data)
    }
    
    public func sendSettings(_ packet: SettingsPacket) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x03, payload: data)
    }
    
    public func sendDeviceInfo() {
        let packet = DeviceInfoPacket(deviceName: DeviceName.current(for: .child))
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x04, payload: data)
    }
    
    private func sendFramedMessage(type: UInt8, payload: Data) {
        guard let connection = connection, isConnected else { return }
        
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
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] headerData, _, isComplete, error in
            if let error = error {
                print("[Receive] Header error: \(error)")
                Task { @MainActor in self?.handleDisconnect() }
                return
            }
            
            guard let headerData = headerData, headerData.count == 5 else {
                if isComplete {
                    Task { @MainActor in self?.handleDisconnect() }
                }
                return
            }
            
            let type = headerData[0]
            let lengthData = headerData.subdata(in: 1..<5)
            let length = UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payloadData, _, _, error2 in
                if let error2 = error2 {
                    print("[Receive] Payload error: \(error2)")
                    Task { @MainActor in self?.handleDisconnect() }
                    return
                }
                
                Task { @MainActor [weak self] in
                    if let payloadData = payloadData {
                        if type == 0x01 {
                            self?.onAudioDataReceived?(payloadData)
                        } else if type == 0x02 {
                            if let packet = try? JSONDecoder().decode(HeartbeatPacket.self, from: payloadData) {
                                self?.onHeartbeatReceived?(packet)
                                self?.peerBatteryLevel = packet.batteryLevel
                            }
                        } else if type == 0x03 {
                            if let packet = try? JSONDecoder().decode(SettingsPacket.self, from: payloadData) {
                                self?.onSettingsReceived?(packet)
                            }
                        } else if type == 0x04 {
                            if let packet = try? JSONDecoder().decode(DeviceInfoPacket.self, from: payloadData),
                               !packet.deviceName.isEmpty {
                                self?.connectedDeviceName = packet.deviceName
                                print("[Connection] Peer device name: \(packet.deviceName)")
                            }
                        }
                    }
                    self?.startReceiving()
                }
            }
        }
    }
}
