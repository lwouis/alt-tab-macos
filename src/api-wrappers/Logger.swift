import SwiftyBeaver
import Foundation

class Logger {
    private static let logger = SwiftyBeaver.self
    static let flag = "--logs="

    static func initialize() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        console.levelString.verbose = "VERB"
        console.levelString.debug = "DEBG"
        console.levelString.info = "INFO"
        console.levelString.warning = "WARN"
        console.levelString.error = "ERRO"
        console.format = "$Dyyyy-MM-dd HH:mm:ss.SSS$d $C$L$c $N.swift:$l $F - $M"
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

    private static func custom(_ level: SwiftyBeaver.Level, _ items: Any..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0)" }.joined(separator: " ")
        logger.custom(level: level, message: message, file: file, function: function, line: line, context: context)
    }
}
