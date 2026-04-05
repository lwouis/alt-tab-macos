import Foundation

class Bash {
    static func command(_ command: String) -> String? {
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
