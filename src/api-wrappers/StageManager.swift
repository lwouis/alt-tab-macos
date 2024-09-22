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
        let (status, output) = executeProcess(arguments: ["read", "com.apple.WindowManager", "GloballyEnabled"])
        return status == 0 && output == "1"
    }

    static func enable() -> Bool {
        return setEnabled(true)
    }

    static func disable() -> Bool {
        return setEnabled(false)
    }

    private static func setEnabled(_ enabled: Bool) -> Bool {
        let (status, _) = executeProcess(arguments: ["write", "com.apple.WindowManager", "GloballyEnabled", "-bool", enabled ? "true" : "false"])
        return status == 0
    }

    private static func executeProcess(arguments: [String]) -> (Int32, String?) {
        let process = Process()
        process.launchPath = "/usr/bin/defaults"
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading
        process.launch()
        process.waitUntilExit()

        let data = fileHandle.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let output = output, !output.isEmpty {
            logger.d(output)
        }

        return (process.terminationStatus, output)
    }
}
