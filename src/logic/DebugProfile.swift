import Cocoa
import Darwin

class DebugProfile {
    static let intraSeparator = ": "
    static let interSeparator = ", "
    static let bulletPoint = "* "
    static let nestedSeparator = "\n  " + bulletPoint
    static let subscriptionRetriesRegex = try! NSRegularExpression(pattern: "[^0-9]+")

    static func make() -> String {
        let tuples: [(String, String)] = [
            // app
            ("App version", App.version),
            ("App preferences", appPreferences()),
            ("Applications", String(Applications.list.count)),
            ("Windows", listLevel2(Windows.list, appWindow)),
            ("Apps subscription retries", listLevel2(Applications.appsInSubscriptionRetryLoop, subscriptionRetriesForApp)),
            ("Windows subscription retries", listLevel2(Windows.windowsInSubscriptionRetryLoop, subscriptionRetriesForWindow)),
            // os
            ("OS version", ProcessInfo.processInfo.operatingSystemVersionString),
            ("OS architecture", Sysctl.run("hw.machine")),
            ("Locale", Locale.current.debugDescription),
            ("Spaces", String(Spaces.allIdsAndIndexes().count)),
            ("Dark mode", Preferences.getString("AppleInterfaceStyle") ?? "Light"),
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

    static func subscriptionRetriesForWindow(_ subscriptionId: String) -> String {
        let range = NSMakeRange(0, subscriptionId.count)
        let widString = subscriptionRetriesRegex.stringByReplacingMatches(in: subscriptionId, range: range, withTemplate: "")
        let wid = try! CGWindowID(NumberFormatter().number(from: widString)!)
        let window = (CGWindowListCopyWindowInfo(.optionAll, wid) as! [CGWindow]).first!
        return listLevel3([
            ("wid", widString),
            ("title", window.title() ?? "nil"),
            ("ownerPID", window.ownerPID().flatMap { String($0) } ?? "nil"),
            ("ownerName", window.ownerName() ?? "nil"),
            ("layer", window.layer().flatMap { String($0) } ?? "nil"),
        ])
    }

    static func subscriptionRetriesForApp(_ subscriptionId: String) -> String {
        let range = NSMakeRange(0, subscriptionId.count)
        let pidString = subscriptionRetriesRegex.stringByReplacingMatches(in: subscriptionId, range: range, withTemplate: "")
        let pid = try! pid_t(NumberFormatter().number(from: pidString)!)
        let app = NSRunningApplication(processIdentifier: pid)!
        return listLevel3([
            ("pid", pidString),
            ("bundleIdentifier", app.bundleIdentifier ?? "nil"),
            ("bundleURL", app.bundleURL?.path ?? "nil"),
        ])
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
            ("isMinimized", String(window.isMinimized)),
            ("isHidden", String(window.isHidden)),
            ("isOnAllSpaces", String(window.isOnAllSpaces)),
            ("spaceId", window.spaceId.flatMap { String($0) } ?? "nil"),
            ("spaceIndex", window.spaceIndex.flatMap { String($0) } ?? "nil"),
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
