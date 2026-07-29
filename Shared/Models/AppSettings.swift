import Foundation

final class AppSettings: ObservableObject {
    @Published var isVOXEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isVOXEnabled, forKey: "isVOXEnabled") }
    }
    
    @Published var voxSensitivity: Double = 0.15 {
        didSet { UserDefaults.standard.set(voxSensitivity, forKey: "voxSensitivity") }
    }
    
    @Published var isDisconnectAlarmEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isDisconnectAlarmEnabled, forKey: "isDisconnectAlarmEnabled") }
    }
    
    @Published var heartbeatInterval: TimeInterval = 2.0 {
        didSet { UserDefaults.standard.set(heartbeatInterval, forKey: "heartbeatInterval") }
    }
    
    init() {
        if UserDefaults.standard.object(forKey: "isVOXEnabled") != nil {
            self.isVOXEnabled = UserDefaults.standard.bool(forKey: "isVOXEnabled")
        }
        if UserDefaults.standard.object(forKey: "voxSensitivity") != nil {
            self.voxSensitivity = UserDefaults.standard.double(forKey: "voxSensitivity")
        }
        if UserDefaults.standard.object(forKey: "isDisconnectAlarmEnabled") != nil {
            self.isDisconnectAlarmEnabled = UserDefaults.standard.bool(forKey: "isDisconnectAlarmEnabled")
        }
    }
}
