import Cocoa
import Darwin

class DebugProfile {
    static let intraSeparator = ": "
    static let interSeparator = ", "
    static let bulletPoint = "* "
    static let nestedSeparator = "\n  " + bulletPoint

    static func make() -> String {
        let tuples: [(String, String)] = [
            // app
            ("App version", App.version),
            ("App preferences", appPreferences()),
            ("Applications count", String(Applications.list.count)),
            ("Windows", appWindows()),
            // os
            ("OS version", ProcessInfo.processInfo.operatingSystemVersionString),
            ("OS architecture", Sysctl.run("hw.machine")),
            ("Locale", Locale.current.debugDescription),
            ("Spaces count", String((CGSCopyManagedDisplaySpaces(cgsMainConnectionId) as! [NSDictionary]).map { (display: NSDictionary) -> Any? in display["Spaces"] }.count)),
            ("Dark mode", Preferences.getString("AppleInterfaceStyle") ?? "Light"),
            ("\"Displays have separate Spaces\"", NSScreen.screensHaveSeparateSpaces ? "checked" : "unchecked"),
            // hardware
            ("Hardware model", Sysctl.run("hw.model")),
            ("Screens count", String(NSScreen.screens.count)),
            ("CPU model", Sysctl.run("machdep.cpu.brand_string")),
            ("Memory size", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .file)),
            // TODO: add gpu model(s)
            // hardware utilization
            ("Active CPU count", Sysctl.run("hw.activecpu", UInt.self).flatMap { (cpu: UInt) -> String in String(cpu) } ?? ""),
            ("Current CPU frequency", Sysctl.run("hw.cpufrequency", Int.self).map { (frequency: Int) -> String in String(format: "%.1f", Double(frequency) / Double(1_000_000_000)) + " Ghz" } ?? ""),
            // TODO: CPU utilization
            // TODO: Active GPU
            // TODO: GPU utilization
            // TODO: Memory utilization
            // TODO: disk space to detect disk pressure
            // TODO: thermals to check if overheating
            // TODO: battery to check if low-energy mode / throttling
        ]
        return tuplesToString(tuples)
    }

    private static func tuplesToString(_ tuples: [(String, String)]) -> String {
        return tuples.map { bulletPoint + $0.0 + intraSeparator + $0.1 }
                .joined(separator: "\n")
    }

    private static func appPreferences() -> String {
        return nestedSeparator + Preferences.all
                .sorted { $0.0 < $1.0 }
                .map { $0.key + intraSeparator + appPreference($0.key) }
                .joined(separator: nestedSeparator)
    }

    private static func appPreference(_ key: String) -> String {
        if let preference = defaults.object(forKey: key) {
            return String(describing: preference)
        }
        return "nil"
    }

    private static func appWindows() -> String {
        return nestedSeparator + Windows.list
                .sorted { $0.cgWindowId < $1.cgWindowId }
                .map { appWindow($0) }
                .joined(separator: nestedSeparator)
    }

    private static func appWindow(_ window: Window) -> String {
        return "{" + ([
            ("isMinimized", String(window.isMinimized)),
            ("isHidden", String(window.isHidden)),
            ("isOnAllSpaces", String(window.isOnAllSpaces)),
            ("spaceId", window.spaceId.flatMap { String($0) } ?? ""),
            ("spaceIndex", window.spaceIndex.flatMap { String($0) } ?? ""),
        ] as [(String, String)])
                .map { $0.0 + intraSeparator + $0.1 }
                .joined(separator: interSeparator)
                + "}"
    }
}
