import Foundation

class PerfLogger {
    private static let logFile = "/tmp/alttab_perf.log"
    
    static func log(_ message: String) {
        #if DEBUG
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] [PERF] \(message)\n"
        
        // Also print to console with NSLog for immediate visibility
        NSLog("[PERF] \(message)")
        
        // Write to file synchronously
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let fileHandle = FileHandle(forWritingAtPath: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
        #endif
    }
    
    static func clear() {
        #if DEBUG
        try? FileManager.default.removeItem(atPath: logFile)
        #endif
    }
}
