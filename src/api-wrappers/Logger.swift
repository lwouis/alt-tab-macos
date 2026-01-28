import SwiftyBeaver
import Foundation

/// General-purpose logger for runtime diagnostics, errors, and debugging
/// Uses SwiftyBeaver for flexible destination management
/// Inherits common utilities from BaseLogger
class Logger: BaseLogger {
    private static let logger = SwiftyBeaver.self
    static let flag = "--logs="

    #if DEBUG
    static let perfLogFile = "/tmp/alttab_perf.log"
    #endif

    static func initialize() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        console.levelString.verbose = "VERB"
        console.levelString.debug = "DEBG"
        console.levelString.info = "INFO"
        console.levelString.warning = "WARN"
        console.levelString.error = "ERRO"
        console.format = "$C$D\(BaseLogger.longDateTimeFormat)$d $L$c $N.swift:$l $F $M"
        console.minLevel = decideLevel()
        logger.addDestination(console)

        #if DEBUG
        // Clear previous log and start fresh for this session
        BaseLogger.removeFile(perfLogFile)

        // Add file destination for performance logs in DEBUG builds
        let file = FileDestination()
        file.logFileURL = URL(fileURLWithPath: perfLogFile)
        file.format = "$D\(BaseLogger.shortDateTimeFormat)$d $M"
        file.minLevel = .verbose  // Only write verbose (PERF) and higher
        logger.addDestination(file)

        // Log build identifier at startup
        logBuildInfo()
        #endif
    }

    #if DEBUG
    private static func logBuildInfo() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        #if DEBUG
        let config = "Debug"
        #else
        let config = "Release"
        #endif

        perf("═══════════════════════════════════════════════════════════")
        perf("AltTab Performance Log Started")
        perf("Version: \(version) (build \(build))")
        perf("Configuration: \(config)")
        perf("Log file: \(perfLogFile)")
        perf("Timestamp: \(BaseLogger.timestamp(format: BaseLogger.longDateTimeFormat))")
        perf("═══════════════════════════════════════════════════════════")
    }
    #endif

    static func decideLevel() -> SwiftyBeaver.Level {
        if let level = (CommandLine.arguments.first { $0.starts(with: flag) })?.dropFirst(flag.count) {
            switch level {
                case "verbose": return .verbose
                case "debug": return .debug
                case "info": return .info
                case "warning": return .warning
                case "error": return .error
                default: break
            }
        }
        return .error
    }

    static func debug(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .debug, file: file, function: function, line: line, context: context, message)
    }

    static func info(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .info, file: file, function: function, line: line, context: context, message)
    }

    static func warning(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .warning, file: file, function: function, line: line, context: context, message)
    }

    static func error(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .error, file: file, function: function, line: line, context: context, message)
    }

    private static func custom(level: SwiftyBeaver.Level, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil, _ message: @escaping () -> Any?) {
        // Use BaseLogger's threadName() instead of local implementation
        logger.custom(level: level, message: { "[\(BaseLogger.threadName())] \(message())" }(), file: file, function: function, line: line, context: context)
    }
}

// MARK: - Performance Logging (DEBUG only, zero overhead in Release)

extension Logger {
    /// Performance log message (compiles away in Release)
    @inline(__always)
    static func perf(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        // Use verbose level for performance logs
        let msg = message() // Evaluate autoclosure first
        custom(level: .verbose, file: file, function: function, line: line, context: nil) {
            "[PERF] \(msg)"
        }
        #endif
    }

    /// Measure execution time of a code block (zero overhead in Release)
    @inline(__always)
    @discardableResult
    static func measure<T>(
        _ name: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () -> T
    ) -> T {
        #if DEBUG
        let start = BaseLogger.preciseTimestamp()
        let result = block()
        let elapsed = BaseLogger.elapsedMilliseconds(from: start)
        perf("\(name()) took \(BaseLogger.formatDuration(elapsed))", file: file, function: function, line: line)
        return result
        #else
        return block()
        #endif
    }

    /// Measure execution time of an async code block (zero overhead in Release)
    @inline(__always)
    @discardableResult
    static func measureAsync<T>(
        _ name: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () async -> T
    ) async -> T {
        #if DEBUG
        let start = BaseLogger.preciseTimestamp()
        let result = await block()
        let elapsed = BaseLogger.elapsedMilliseconds(from: start)
        perf("\(name()) took \(BaseLogger.formatDuration(elapsed))", file: file, function: function, line: line)
        return result
        #else
        return await block()
        #endif
    }

    /// Measure multiple steps within a larger operation (zero overhead in Release)
    @inline(__always)
    @discardableResult
    static func section<T>(
        _ name: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (PerfSection) -> T
    ) -> T {
        #if DEBUG
        let sectionName = name()
        perf("===== \(sectionName) START =====", file: file, function: function, line: line)
        let overallStart = BaseLogger.preciseTimestamp()
        let section = PerfSection()
        let result = block(section)
        let overallElapsed = BaseLogger.elapsedMilliseconds(from: overallStart)
        perf("===== \(sectionName) TOTAL: \(BaseLogger.formatDuration(overallElapsed)) =====", file: file, function: function, line: line)
        return result
        #else
        return block(PerfSection())
        #endif
    }

    /// Log cache hit with consistent formatting (zero overhead in Release)
    @inline(__always)
    static func cacheHit(
        _ name: @autoclosure () -> String,
        details: @autoclosure () -> String = "",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let detailStr = details()
        perf("\(name()): cache HIT\(detailStr.isEmpty ? "" : " - \(detailStr)")", file: file, function: function, line: line)
        #endif
    }

    /// Log cache miss with consistent formatting (zero overhead in Release)
    @inline(__always)
    static func cacheMiss(
        _ name: @autoclosure () -> String,
        reason: @autoclosure () -> String = "",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let reasonStr = reason()
        perf("\(name()): cache MISS\(reasonStr.isEmpty ? "" : " - \(reasonStr)")", file: file, function: function, line: line)
        #endif
    }
}

// MARK: - PerfSection (for measuring multiple steps)

class PerfSection {
    /// Measure a step within a section (zero overhead in Release)
    @inline(__always)
    @discardableResult
    func step<T>(
        _ name: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () -> T
    ) -> T {
        #if DEBUG
        let start = BaseLogger.preciseTimestamp()
        let result = block()
        let elapsed = BaseLogger.elapsedMilliseconds(from: start)
        Logger.perf("\(name()) took \(BaseLogger.formatDuration(elapsed))", file: file, function: function, line: line)
        return result
        #else
        return block()
        #endif
    }

    /// Log a message within a section (zero overhead in Release)
    @inline(__always)
    func log(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.perf(message(), file: file, function: function, line: line)
    }
}
