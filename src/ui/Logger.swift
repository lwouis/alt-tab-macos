import SwiftyBeaver
import Foundation

let logger = SwiftyBeaver.self

class Logger {
    static let flag = "--logs="

    static func initialize() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        console.levelString.verbose = "VERB"
        console.levelString.debug = "DEBG"
        console.levelString.info = "INFO"
        console.levelString.warning = "WARN"
        console.levelString.error = "ERRO"
        console.format = "$C$DHH:mm:ss$d $L$c $N.swift:$l $F $M"
        console.minLevel = decideLevel()
        logger.addDestination(console)
    }

    static func decideLevel() -> SwiftyBeaver.Level {
        if let level = CommandLine.arguments.first { $0.starts(with: flag) }?.substring(from: flag.endIndex) {
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
