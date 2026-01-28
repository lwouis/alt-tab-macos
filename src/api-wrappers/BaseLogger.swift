import Foundation

/// Base logging utilities for the unified Logger
/// Provides common functionality for thread tracking, formatting, and metadata
class BaseLogger {

    // MARK: - Thread Tracking

    /// Get the name of the current thread
    /// Returns "main" for main thread, thread name if set, or queue label
    static func threadName() -> String {
        if Thread.isMainThread {
            return "main"
        } else if let name = Thread.current.name, !name.isEmpty {
            return name
        } else {
            let name = __dispatch_queue_get_label(nil)
            return String(cString: name, encoding: .utf8) ?? Thread.current.description
        }
    }

    // MARK: - File Path Utilities

    /// Extract just the filename from a full file path
    /// Example: "/path/to/MyFile.swift" -> "MyFile.swift"
    static func fileName(from filePath: String) -> String {
        return (filePath as NSString).lastPathComponent
    }

    /// Extract function name without signature
    /// Example: "myFunction(param:)" -> "myFunction"
    static func simpleFunctionName(from function: String) -> String {
        // Remove everything after the first (
        if let parenIndex = function.firstIndex(of: "(") {
            return String(function[..<parenIndex])
        }
        return function
    }

    // MARK: - Timestamp Formatting

    /// Standard timestamp format for logs
    static let longDateTimeFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    static let shortDateTimeFormat = "HH:mm:ss.SSS"
    static let veryShortDateTimeFormat = "HH:mm:ss"

    /// Get formatted timestamp string
    static func timestamp(format: String = shortDateTimeFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }

    // MARK: - Log Entry Formatting

    /// Format a complete log entry with all metadata
    /// - Parameters:
    ///   - level: Log level (e.g., "DEBG", "PERF")
    ///   - message: The log message
    ///   - file: Source file path
    ///   - function: Function name
    ///   - line: Line number
    ///   - includeDate: Whether to include date in timestamp
    /// - Returns: Formatted log string
    static func formatLogEntry(
        level: String,
        message: String,
        file: String,
        function: String,
        line: Int,
        includeDate: Bool = false
    ) -> String {
        let ts = timestamp(format: includeDate ? longDateTimeFormat : shortDateTimeFormat)
        let thread = threadName()
        let file = fileName(from: file)

        return "[\(ts)] [\(thread)] [\(level)] \(file):\(line) \(function) - \(message)"
    }

    // MARK: - Performance Measurement Utilities

    /// High-precision timestamp for performance measurement
    static func preciseTimestamp() -> UInt64 {
        return DispatchTime.now().uptimeNanoseconds
    }

    /// Calculate elapsed time in milliseconds
    /// - Parameters:
    ///   - start: Start timestamp from preciseTimestamp()
    ///   - end: End timestamp from preciseTimestamp() (defaults to now)
    /// - Returns: Elapsed time in milliseconds
    static func elapsedMilliseconds(from start: UInt64, to end: UInt64? = nil) -> Double {
        let endTime = end ?? preciseTimestamp()
        return Double(endTime - start) / 1_000_000
    }

    /// Format elapsed time as a string
    /// - Parameter milliseconds: Time in milliseconds
    /// - Returns: Formatted string (e.g., "1.23ms", "123.45ms")
    static func formatDuration(_ milliseconds: Double) -> String {
        if milliseconds < 1.0 {
            return String(format: "%.3fms", milliseconds)
        } else if milliseconds < 100.0 {
            return String(format: "%.2fms", milliseconds)
        } else {
            return String(format: "%.1fms", milliseconds)
        }
    }

    // MARK: - File Utilities

    /// Write data to a log file, creating if needed
    /// - Parameters:
    ///   - data: Data to write
    ///   - path: File path
    ///   - append: Whether to append (true) or overwrite (false)
    static func writeToFile(_ data: Data, path: String, append: Bool = true) {
        if FileManager.default.fileExists(atPath: path) {
            if append, let fileHandle = FileHandle(forWritingAtPath: path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    /// Remove a log file if it exists
    /// - Parameter path: File path to remove
    static func removeFile(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
