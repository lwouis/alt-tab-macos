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
            ("Applications", String(Applications.list.count)),
            ("Windows", listLevel2(Windows.list, appWindow)),
            // os
            ("OS version", ProcessInfo.processInfo.operatingSystemVersionString),
            ("OS architecture", Sysctl.run("hw.machine")),
            ("Locale", Locale.current.debugDescription),
            ("Spaces", String(Spaces.idsAndIndexes.count)),
            ("Dark mode", defaults.string(forKey: "AppleInterfaceStyle") ?? "Light"),
            ("\"Displays have separate Spaces\"", NSScreen.screensHaveSeparateSpaces ? "checked" : "unchecked"),
            // hardware
            ("Hardware model", Sysctl.run("hw.model")),
            ("Screens", listLevel2(NSScreen.screens, screen)),
            ("CPU model", Sysctl.run("machdep.cpu.brand_string")),
            ("Memory size", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .file)),
            // hardware utilization
            ("Active CPU count", Sysctl.run("hw.activecpu", UInt.self).flatMap { (cpu: UInt) -> String in String(cpu) } ?? "nil"),
            ("Current CPU frequency", Sysctl.run("hw.cpufrequency", Int.self).map { (frequency: Int) -> String in String(format: "%.1f", Double(frequency) / Double(1_000_000_000)) + " Ghz" } ?? "nil"),
            ("Resource utilization", resourcesUtilization()),
        ]
        return listLevel1(tuples)
    }

    private static func listLevel1(_ tuples: [(String, String)]) -> String {
        tuples.map { bulletPoint + $0.0 + intraSeparator + $0.1 }
            .joined(separator: "\n")
    }

    static func listLevel2<A>(_ array: [A], _ itemTransformationFn: (A) -> String) -> String {
        if array.count == 0 {
            return "0"
        }
        return String(array.count) + nestedSeparator + array
            .map { itemTransformationFn($0) }
            .joined(separator: nestedSeparator)
    }

    private static func listLevel3(_ attributes: [(String, String)]) -> String {
        return "{" + attributes
            .map { $0.0 + intraSeparator + $0.1 }
            .joined(separator: interSeparator)
            + "}"
    }

    private static func appPreferences() -> String {
        nestedSeparator + Preferences.all
            .sorted { $0.0 < $1.0 }
            .map { $0.key + intraSeparator + appPreference($0.key) }
            .joined(separator: nestedSeparator)
    }

    private static func appPreference(_ key: String) -> String {
        defaults.object(forKey: key).map { String(describing: $0) } ?? "nil"
    }

    private static func screen(_ screen: NSScreen) -> String {
        let frame = screen.frame
        return listLevel3([
            ("x", frame.origin.x.description),
            ("y", frame.origin.y.description),
            ("width", frame.size.width.description),
            ("height", frame.size.height.description),
        ])
    }

    private static func appWindow(_ window: Window) -> String {
        return listLevel3([
            ("isFullscreen", String(window.isFullscreen)),
            ("isWindowlessApp", String(window.isWindowlessApp)),
            ("isMinimized", String(window.isMinimized)),
            ("isHidden", String(window.isHidden)),
            ("isTabbed", String(window.isTabbed)),
            ("isOnAllSpaces", String(window.isOnAllSpaces)),
            ("shouldShowTheUser", String(window.shouldShowTheUser)),
            ("spaceId", String(window.spaceId)),
            ("spaceIndex", String(window.spaceIndex)),
        ])
    }

    private static func resourcesUtilization() -> String {
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
