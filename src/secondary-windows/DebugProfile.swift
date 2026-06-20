import Cocoa
import Darwin
import Carbon.HIToolbox.TextInputSources

class DebugProfile {
    static let intraSeparator = ": "
    static let interSeparator = ", "
    static let bulletPoint = "* "
    static let nestedSeparator = "\n  " + bulletPoint

    /// Must be called on the main thread: it reads TIS/AppKit/model state that's main-thread-only. The
    /// riskiest is `Preferences.all`, whose first access lazily inits `defaultValues` → `defaultShortcut(...)`
    /// → ShortcutRecorder → `TISCopyCurrentASCIICapableKeyboardLayoutInputSource`, and TIS trips a libdispatch
    /// main-queue precondition (SIGTRAP) off-main on macOS 26. The feedback submit path calls us on main; the
    /// crash-report `attachments` delegate hops to main at its call site.
    static func make() -> String {
        let tuples: [(String, String)] = [
            // identity — kept first so the backend can extract these lines if it wants to
            // surface them outside the collapsible <details> section.
            ("App", "\(App.name) v\(App.version)"),
            ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            ("License", LicenseManager.shared.state.debugProfileLabel),
            // app
            ("App preferences", appPreferences()),
            ("Applications", String(Applications.list.count)),
            ("Windows", String(Windows.list.count)),
            // os
            ("OS architecture", Sysctl.run("hw.machine")),
            ("Locale", Locale.current.debugDescription),
            ("InputSource", inputSource()),
            ("Spaces", String(Spaces.idsAndIndexes.count)),
            ("Dark mode", UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"),
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
            .map { $0.key + intraSeparator + String(describing: $0.value) }
            .joined(separator: nestedSeparator)
    }

    private static func screen(_ screen: NSScreen) -> String {
        let frame = screen.frame
        return listLevel3([
            ("x", frame.origin.x.description),
            ("y", frame.origin.y.description),
            ("width", frame.size.width.description),
            ("height", frame.size.height.description),
            ("scale", String(format: "%.2f", screen.backingScaleFactor)),
            ("dpi", dpi(of: screen) ?? "unknown"),
        ])
    }

    private static func dpi(of screen: NSScreen) -> String? {
        // `physicalSize()` (mm) is from the NSScreen extension in Screens.swift; it can return
        // nil when CGDisplayScreenSize reports zero (mirrored displays, some VMs). Combine
        // with the pixel width (logical width × backingScaleFactor) to get dots-per-inch.
        guard let physicalMm = screen.physicalSize(), physicalMm.width > 0 else { return nil }
        let pixelWidth = screen.frame.width * screen.backingScaleFactor
        let widthInches = physicalMm.width / 25.4
        return String(format: "%.0f", pixelWidth / widthInches)
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

    static func inputSource() -> String {
        // `currentInputSource()`'s TIS APIs require the main thread; `make()` guarantees we're on it.
        return InputSourceEvents.currentInputSource()
    }
}
