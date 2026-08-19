import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        localizationBundle().localizedString(forKey: key, value: nil, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: AppLanguage.stored.resolvedLocale, arguments: arguments)
    }

    private static func localizationBundle() -> Bundle {
        let code = AppLanguage.stored.resolvedLanguageCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    enum Common {
        static var back: String { t("common.back") }
        static var done: String { t("common.done") }
        static var settings: String { t("common.settings") }
        static var searching: String { t("common.searching") }
        static var connecting: String { t("common.connecting") }
    }

    enum Role {
        static var child: String { t("role.child") }
        static var parent: String { t("role.parent") }
        static var childSubtitle: String { t("role.child.subtitle") }
        static var parentSubtitle: String { t("role.parent.subtitle") }
    }

    enum Device {
        static var childDefault: String { t("device.default.child") }
        static var parentDefault: String { t("device.default.parent") }
    }

    enum Connection {
        static var disconnected: String { t("connection.disconnected") }
        static var searching: String { t("connection.searching") }
        static var wifi: String { t("connection.wifi") }
        static var p2p: String { t("connection.p2p") }
        static func latency(_ ms: Int) -> String { format("connection.latency", ms) }
        static func signal(_ dbm: Int) -> String { format("connection.signal", dbm) }
        static func a11yLatency(_ ms: Int) -> String { format("connection.a11y.latency", ms) }
        static func a11ySignal(_ dbm: Int) -> String { format("connection.a11y.signal", dbm) }
    }

    enum Child {
        static var pairingPin: String { t("child.pairingPin") }
        static var openConnection: String { t("child.openConnection") }
        static var transmitting: String { t("child.transmitting") }
        static var micOn: String { t("child.micOn") }
        static var parentSpeaking: String { t("child.parentSpeaking") }
        static var waiting: String { t("child.waiting") }
        static var lockHint: String { t("child.lockHint") }
    }

    enum Parent {
        static var backToList: String { t("parent.backToList") }
        static func enterPin(_ name: String) -> String { format("parent.enterPin", name) }
        static var wrongPin: String { t("parent.wrongPin") }
        static var selectChild: String { t("parent.selectChild") }
        static var reconnecting: String { t("parent.reconnecting") }
        static var p2pHint: String { t("parent.p2pHint") }
        static var restoringLast: String { t("parent.restoringLast") }
        static var tapDirect: String { t("parent.tapDirect") }
        static var trusted24h: String { t("parent.trusted24h") }
        static var tapPin: String { t("parent.tapPin") }
        static var lostBang: String { t("parent.lostBang") }
        static var lost: String { t("parent.lost") }
        static var lowBattery: String { t("parent.lowBattery") }
        static var speaking: String { t("parent.speaking") }
        static var receiving: String { t("parent.receiving") }
        static var listening: String { t("parent.listening") }
        static var restoring: String { t("parent.restoring") }
        static func babyBattery(_ percent: Int) -> String { format("parent.babyBattery", percent) }
        static var holdToTalk: String { t("parent.holdToTalk") }
    }

    enum Settings {
        static var title: String { t("settings.title") }
        static var device: String { t("settings.device") }
        static var deviceName: String { t("settings.deviceName") }
        static var audio: String { t("settings.audio") }
        static var vox: String { t("settings.vox") }
        static var voxHelp: String { t("settings.voxHelp") }
        static var sensitivity: String { t("settings.sensitivity") }
        static var holdAfterDetection: String { t("settings.holdAfterDetection") }
        static var alerts: String { t("settings.alerts") }
        static var disconnectAlarm: String { t("settings.disconnectAlarm") }
        static var alarmDelay: String { t("settings.alarmDelay") }
        static var disconnectAlarmHelp: String { t("settings.disconnectAlarmHelp") }
        static var lowBatteryAlert: String { t("settings.lowBatteryAlert") }
        static var batteryThreshold: String { t("settings.batteryThreshold") }
        static var lowBatteryHelp: String { t("settings.lowBatteryHelp") }
        static var autoReconnect: String { t("settings.autoReconnect") }
        static var autoReconnectHelp: String { t("settings.autoReconnectHelp") }
        static var security: String { t("settings.security") }
        static var requirePin: String { t("settings.requirePin") }
        static func pinHelp(_ appName: String) -> String { format("settings.pinHelp", appName) }
        static var about: String { t("settings.about") }
        static var version: String { t("settings.version") }
        static var language: String { t("settings.language") }
        static var languageSystem: String { t("settings.languageSystem") }
        static var languageHelp: String { t("settings.languageHelp") }
    }

    enum Auth {
        static var invalidPin: String { t("auth.invalidPin") }
        static var failed: String { t("auth.failed") }

        static func message(fromNetwork value: String?) -> String {
            switch value {
            case "invalid_pin", "Neplatný PIN":
                return invalidPin
            default:
                return failed
            }
        }
    }

    enum Hint {
        static var networkChangedRestore: String { t("hint.networkChangedRestore") }
        static func connecting(to name: String) -> String { format("hint.connecting", name) }
        static var connectTimeout: String { t("hint.connectTimeout") }
        static var waitingP2P: String { t("hint.waitingP2P") }
        static var networkChangedRetry: String { t("hint.networkChangedRetry") }
        static var connectionFailed: String { t("hint.connectionFailed") }
        static var lookingWifiP2P: String { t("hint.lookingWifiP2P") }
        static var lookingP2PNoRouter: String { t("hint.lookingP2PNoRouter") }
        static var restoring: String { t("hint.restoring") }
        static var interrupted: String { t("hint.interrupted") }
        static var searchingBabyP2P: String { t("hint.searchingBabyP2P") }
        static func attemptP2P(_ attempt: Int) -> String { format("hint.attemptP2P", attempt) }
    }
}
