import Foundation

enum LogLevel: Int, Comparable {
    case debug = 0
    case info
    case warning
    case error

    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var word: String {
        switch self {
            case .debug: return "DEBG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERRO"
        }
    }

    /// xterm-256 color codes that match SwiftyBeaver's defaults (useTerminalColors = true).
    var ansiColorStart: String {
        switch self {
            case .debug: return "\u{001B}[38;5;35m"
            case .info: return "\u{001B}[38;5;38m"
            case .warning: return "\u{001B}[38;5;178m"
            case .error: return "\u{001B}[38;5;197m"
        }
    }
}

class Logger {
    static let flag = "--logs="
    static var minLevel: LogLevel = .error
    /// Is `.debug` being emitted? Callers use this to skip building an expensive line (the per-show tile
    /// dump walks every window).
    ///
    /// There is exactly ONE log channel, deliberately. A second stream bypassing `minLevel` splits a bug
    /// report in half — a reporter on `--logs=debug` gets everything except what the second channel took —
    /// and `open --args` drops arguments when AltTab is already running, so "relaunch with the extra flag"
    /// produces a capture that merely looks complete (#5785). Gate a noisy line instead of forking the
    /// stream.
    static var debugEnabled: Bool { minLevel <= .debug }
    private static var tap: ((LogLevel, String) -> Void)?
    private static let ansiReset = "\u{001B}[0m"
    private static let writeQueue = DispatchQueue(label: "Logger.writeQueue", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func initialize() {
        minLevel = decideLevel()
    }

    static func decideLevel() -> LogLevel {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix(flag) }) else { return .error }
        switch String(arg.dropFirst(flag.count)) {
            case "debug", "verbose": return .debug
            case "info": return .info
            case "warning": return .warning
            case "error": return .error
            default: return .error
        }
    }

    static func setTap(_ tap: ((LogLevel, String) -> Void)?) { self.tap = tap }

    static func debug(_ message: () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.debug, message, file, function, line)
    }

    static func info(_ message: () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.info, message, file, function, line)
    }

    static func warning(_ message: () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.warning, message, file, function, line)
    }

    static func error(_ message: () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.error, message, file, function, line)
    }

    @inline(__always)
    private static func emit(_ level: LogLevel, _ message: () -> Any?, _ file: String, _ function: String, _ line: Int) {
        // Keep message parameters nonescaping: captured closures can otherwise be allocated before
        // this inline guard, even when the message is suppressed.
        guard level >= minLevel else { return }
        emitEnabled(level, message, file, function, line)
    }

    @inline(never)
    private static func emitEnabled(_ level: LogLevel, _ message: () -> Any?, _ file: String, _ function: String, _ line: Int) {
        let rendered = "\(message() ?? "nil")"
        let now = Date()
        let thread = threadName()
        // Move formatting + IO off the calling thread (typically main on the hot path).
        writeQueue.async {
            let fileName = (file as NSString).lastPathComponent
            // SwiftyBeaver console.format was: "$C$D{HH:mm:ss.SSS}$d $L$c $N.swift:$l $F $M"
            // with $M wrapped as "[\(threadName())] \(message())".
            let timestamp = dateFormatter.string(from: now)
            let head = "\(timestamp) \(level.word)"
            let body = "\(fileName):\(line) \(cleanFunctionName(function)) [\(thread)] \(rendered)"
            // Always emit ANSI colors — matches SwiftyBeaver's useTerminalColors=true behavior.
            // Modern terminals (Terminal.app, iTerm2, VS Code, etc.) all render them; logs piped
            // to files keep the codes harmlessly inline.
            print("\(level.ansiColorStart)\(head)\(ansiReset) \(body)")
            if let tap {
                // DebugWindow already does its own per-level coloring; pass the uncolored line.
                tap(level, "\(head) \(body)")
            }
        }
    }

    /// Swift's #function returns the full signature, including "_:" placeholders for unnamed
    /// parameters (e.g. "init(_:_:_:_:)"). Strip those — the log already has file:line, the
    /// arity is noise. Functions with labeled arguments keep their labels.
    private static func cleanFunctionName(_ s: String) -> String {
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")"), open < close else { return s }
        let args = s[s.index(after: open)..<close]
        if args.isEmpty || args.allSatisfy({ $0 == "_" || $0 == ":" }) {
            return "\(s[..<open])()"
        }
        return s
    }

    private static func threadName() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        let label = __dispatch_queue_get_label(nil)
        return String(cString: label, encoding: .utf8) ?? Thread.current.description
    }
}
