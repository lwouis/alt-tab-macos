import Foundation

class StageManager {

    private static var enabled = false
    private static var checkEnabledCount = 0

    static func isEnabledWithCache() -> Bool {
        if checkEnabledCount == 1 { return enabled }
        checkEnabledCount += 1
        enabled = isEnabled()
        return enabled
    }

    static func isEnabled() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.WindowManager", "GloballyEnabled"]

        let pipe = Pipe()
        task.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading

        task.launch()
        let data = fileHandle.readDataToEndOfFile()
        task.waitUntilExit()

        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return output == "1"
        }
        return false
    }

    static func enable() -> Bool {
        return setEnabled(true)
    }

    static func disable() -> Bool {
        return setEnabled(false)
    }

    private static func setEnabled(_ enabled: Bool) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.WindowManager", "GloballyEnabled", "-bool", enabled ? "true" : "false"]

        let pipe = Pipe()
        task.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading

        task.launch()
        task.waitUntilExit()

        let data = fileHandle.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8), output.count > 0 {
            logger.d(output)
        }

        return task.terminationStatus == 0
    }
}
