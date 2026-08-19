import Foundation

@MainActor
enum DeviceName {
    static let storageKey = "deviceName"
    static var childDefault: String { L10n.Device.childDefault }
    static var parentDefault: String { L10n.Device.parentDefault }

    /// Appended to the Bonjour instance name after the PIN part — always visible to the parent
    /// browser without relying on TXT records.
    static let serviceSeparator = "~"

    static func defaultName(for role: AppRole) -> String {
        switch role {
        case .parent:
            return parentDefault
        case .child, .none:
            return childDefault
        }
    }

    static func current(for role: AppRole) -> String {
        let custom = (UserDefaults.standard.string(forKey: storageKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultName(for: role) : custom
    }

    static func labelForService(availableBytes: Int, role: AppRole) -> String {
        var name = current(for: role).replacingOccurrences(of: serviceSeparator, with: " ")
        while name.utf8.count > availableBytes, !name.isEmpty {
            name.removeLast()
        }
        return name
    }

    static func displayName(fromServiceInstanceName name: String, txtDeviceName: String?) -> String {
        let parts = name.components(separatedBy: serviceSeparator)
        if parts.count > 1 {
            let fromService = parts.dropFirst().joined(separator: serviceSeparator)
            if !fromService.isEmpty { return fromService }
        }
        if let txtDeviceName, !txtDeviceName.isEmpty { return txtDeviceName }
        return childDefault
    }

    static func pairingPIN(fromServiceInstanceName name: String) -> String {
        let pairingPart = name.components(separatedBy: serviceSeparator)[0]
        return pairingPart.components(separatedBy: "-").last ?? ""
    }
}
