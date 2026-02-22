import SwiftyBeaver
import Foundation

class Logger {
    private static let logger = SwiftyBeaver.self
    static let flag = "--logs="
    static let longDateTimeFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    static let shortDateTimeFormat = "HH:mm:ss"

    static func initialize() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        configureDestination(console)
        console.format = "$C$D\(shortDateTimeFormat)$d $L$c $N.swift:$l $F $M"
        console.minLevel = decideLevel()
        logger.addDestination(console)
    }

    static func configureDestination(_ dest: BaseDestination) {
        dest.levelString.verbose = "VERB"
        dest.levelString.debug = "DEBG"
        dest.levelString.info = "INFO"
        dest.levelString.warning = "WARN"
        dest.levelString.error = "ERRO"
        dest.format = "$D\(shortDateTimeFormat)$d $L $N.swift:$l $F $M"
    }

    @discardableResult
    static func addDestination(_ dest: BaseDestination) -> Bool {
        logger.addDestination(dest)
    }

    @discardableResult
    static func removeDestination(_ dest: BaseDestination) -> Bool {
        logger.removeDestination(dest)
    }

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
        logger.custom(level: level, message: { "[\(threadName())] \(message())" }(), file: file, function: function, line: line, context: context)
    }


    private static func threadName() -> String {
        if Thread.isMainThread {
            return "main"
        } else if let name = Thread.current.name, !name.isEmpty {
            return name
        } else {
            let name = __dispatch_queue_get_label(nil)
            return String(cString: name, encoding: .utf8) ?? Thread.current.description
        }
    }
}

/// custom destination to display logs in the debug window
class DebugWindowDestination: BaseDestination {
    var onNewEntry: ((SwiftyBeaver.Level, String) -> Void)?

    override var defaultHashValue: Int { return 2 }

    override init() {
        super.init()
        Logger.configureDestination(self)
        minLevel = .debug
    }

    override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
                       file: String, function: String, line: Int, context: Any? = nil) -> String? {
        let formattedString = super.send(level, msg: msg, thread: thread,
                                         file: file, function: function, line: line, context: context)
        guard let formatted = formattedString else { return nil }
        let callback = onNewEntry
        DispatchQueue.main.async { callback?(level, formatted) }
        return formattedString
    }
}
