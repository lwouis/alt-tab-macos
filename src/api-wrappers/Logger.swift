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
        console.levelString.verbose = "VERB"
        console.levelString.debug = "DEBG"
        console.levelString.info = "INFO"
        console.levelString.warning = "WARN"
        console.levelString.error = "ERRO"
        console.format = "$C$D\(longDateTimeFormat)$d $L$c $N.swift:$l $F $M"
        console.minLevel = decideLevel()
        logger.addDestination(console)
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

    static func debug(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.debug, items, file: file, function: function, line: line, context: context)
    }

    static func info(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.info, items, file: file, function: function, line: line, context: context)
    }

    static func warning(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.warning, items, file: file, function: function, line: line, context: context)
    }

    static func error(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.error, items, file: file, function: function, line: line, context: context)
    }

    private static func custom(_ level: SwiftyBeaver.Level, _ items: [Any?], file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0 ?? "nil")" }.joined(separator: " ")
        logger.custom(level: level, message: "[\(threadName())] \(message)", file: file, function: function, line: line, context: context)
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
