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
            ("Spaces count", String(Spaces.allIdsAndIndexes().count)),
            ("Dark mode", Preferences.getString("AppleInterfaceStyle") ?? "Light"),
            ("\"Displays have separate Spaces\"", NSScreen.screensHaveSeparateSpaces ? "checked" : "unchecked"),
            // hardware
            ("Hardware model", Sysctl.run("hw.model")),
            ("Screens count", screens()),
            ("CPU model", Sysctl.run("machdep.cpu.brand_string")),
            ("Memory size", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .file)),
            // hardware utilization
            ("Active CPU count", Sysctl.run("hw.activecpu", UInt.self).flatMap { (cpu: UInt) -> String in String(cpu) } ?? ""),
            ("Current CPU frequency", Sysctl.run("hw.cpufrequency", Int.self).map { (frequency: Int) -> String in String(format: "%.1f", Double(frequency) / Double(1_000_000_000)) + " Ghz" } ?? ""),
            ("Resource utilization", resourcesUtilization()),
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
        return String(Windows.list.count) + nestedSeparator + Windows.list
            .sorted { $0.cgWindowId < $1.cgWindowId }
            .map { appWindow($0) }
            .joined(separator: nestedSeparator)
    }

    private static func screens() -> String {
        String(NSScreen.screens.count) + nestedSeparator + NSScreen.screens
            .map { String(describing: $0.frame) }
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

    static func resourcesUtilization() -> String {
        let topOutput = Bash.command("top -pid " + String(ProcessInfo.processInfo.processIdentifier) + " -l 2 -stats \"cpu,mem,threads\" | tail -n 1") ?? ""
        let metrics = topOutput.split(separator: " ")
        if metrics.count >= 3 {
            return nestedSeparator + [
                "CPU\(intraSeparator)\(metrics[0])%",
                "Memory\(intraSeparator)\(metrics[1])",
                "Threads count\(intraSeparator)\(metrics[2])",
            ].joined(separator: nestedSeparator)
        }
        return ""
    }
}
