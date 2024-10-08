import SwiftyBeaver
import Foundation

let logger = SwiftyBeaver.self

class LogManager {
    private static let maxDays = 1  // Set maximum log retention days
    private static var timer: Timer?

    static func setup() {
        setupLogger()
        if ((logger.destinations.first { $0 is FileDestination } as? FileDestination)?.logFileURL != nil) {
            startLogFileCleanupTimer()
        }
    }

    private static func setupLogger() {
        let format = "$Dyyyy-MM-dd HH:mm:ss.SSS$d $C$L$c $N.swift:$l $F - $M"
        let console = ConsoleDestination()
        console.format = format
        let file = FileDestination()
        file.format = format

        #if DEBUG
        console.minLevel = .verbose
        file.minLevel = .verbose
        logger.addDestination(console)
        logger.addDestination(file)
        #else
        console.minLevel = .error
        file.minLevel = .error
//        logger.addDestination(file)
        #endif

        if let logFileURL = file.logFileURL {
            logger.info("Default log file path: \(logFileURL.path)")
        }
    }

    private static func startLogFileCleanupTimer() {
        // Schedule a timer to run every 24 hours to clean up log files
        timer = Timer.scheduledTimer(timeInterval: 86400, target: self, selector: #selector(cleanupLogFiles), userInfo: nil, repeats: true)
        // Set tolerance to save battery
        timer?.tolerance = 3600
    }

    @objc private static func cleanupLogFiles() {
        guard let fileDestination = logger.destinations.first(where: { $0 is FileDestination }) as? FileDestination,
              let logFileURL = fileDestination.logFileURL else { return }

        let fileManager = FileManager.default
        // Get the file attributes to check the creation date
        if let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
           let creationDate = attributes[.creationDate] as? Date {
            // Calculate the expiration date
            let expirationDate = Calendar.current.date(byAdding: .day, value: -maxDays, to: Date())
            // If the log file is older than the specified retention period, delete it
            if creationDate < expirationDate ?? Date() {
                fileDestination.deleteLogFile()
            }
        }
    }
}

extension SwiftyBeaver {

    class func isVerboseEnabled() -> Bool {
        return isEnabled(level: .verbose)
    }

    class func isDebugEnabled() -> Bool {
        return isEnabled(level: .debug)
    }

    class func isInfoEnabled() -> Bool {
        return isEnabled(level: .info)
    }

    class func isWarningEnabled() -> Bool {
        return isEnabled(level: .warning)
    }

    class func isErrorEnabled() -> Bool {
        return isEnabled(level: .error)
    }

    class func isEnabled(level: SwiftyBeaver.Level) -> Bool {
        for destination in logger.destinations {
            if level.rawValue >= destination.minLevel.rawValue {
                return true
            }
        }
        return false
    }

    class func d(_ items: Any..., separator: String = " ", terminator: String = "\n",
                 _ file: String = #file, _ function: String = #function, _ line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0)" }.joined(separator: separator)
        if terminator == "\n" {
            debug(message, file, function, line: line, context: context)
        } else {
            let finalMessage = message + terminator
            debug(finalMessage, file, function, line: line, context: context)
        }
    }

    class func i(_ items: Any..., separator: String = " ", terminator: String = "\n",
                 _ file: String = #file, _ function: String = #function, _ line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0)" }.joined(separator: separator)
        if terminator == "\n" {
            info(message, file, function, line: line, context: context)
        } else {
            let finalMessage = message + terminator
            info(finalMessage, file, function, line: line, context: context)
        }
    }

    class func w(_ items: Any..., separator: String = " ", terminator: String = "\n",
                 _ file: String = #file, _ function: String = #function, _ line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0)" }.joined(separator: separator)
        if terminator == "\n" {
            warning(message, file, function, line: line, context: context)
        } else {
            let finalMessage = message + terminator
            warning(finalMessage, file, function, line: line, context: context)
        }
    }

    class func e(_ items: Any..., separator: String = " ", terminator: String = "\n",
                 _ file: String = #file, _ function: String = #function, _ line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0)" }.joined(separator: separator)
        if terminator == "\n" {
            error(message, file, function, line: line, context: context)
        } else {
            let finalMessage = message + terminator
            error(finalMessage, file, function, line: line, context: context)
        }
    }
}
