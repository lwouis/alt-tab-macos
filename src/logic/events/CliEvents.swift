class CliEvents {
    static let portName = "com.lwouis.alt-tab-macos.cli"

    static func observe() {
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        if let messagePort = CFMessagePortCreateLocal(nil, portName as CFString, handleEvent, &context, nil),
           let source = CFMessagePortCreateRunLoopSource(nil, messagePort, 0) {
            CFRunLoopAddSource(BackgroundWork.cliEventsThread.runLoop, source, .commonModes)
        } else {
            Logger.error("Can't listen on message port. Is another AltTab already running?")
            // TODO: should we quit or restart here?
            // It's complex since AltTab can be restarted sometimes,
            // and the new instance may coexit with the old for some duration
            // There is also the case of multiple instances at login
        }
    }
}

fileprivate func handleEvent(_: CFMessagePort?, _: Int32, _ data: CFData?, _: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
    Logger.debug()
    if let data,
       let message = String(data: data as Data, encoding: .utf8) {
        Logger.info(message)
        let output = CliServer.executeCommandAndSendReponse(message)
        if let responseData = try? CliServer.jsonEncoder.encode(output) as CFData {
            return Unmanaged.passRetained(responseData)
        }
    }
    Logger.error("Failed to decode message")
    return nil
}

class CliServer {
    static let jsonEncoder = JSONEncoder()
    static let error = "error"
    static let noOutput = "noOutput"

    static func executeCommandAndSendReponse(_ rawValue: String) -> Codable {
        var output: Codable = ""
        DispatchQueue.main.sync {
            if rawValue == "--list" {
                output = JsonOutput(windows: Windows.list
                    .filter { !$0.isWindowlessApp }
                    .map { JsonWindow(id: $0.cgWindowId, title: $0.title) }
                )
                return
            }
            if rawValue.hasPrefix("--focus=") {
                if let id = CGWindowID(rawValue.dropFirst("--focus=".count)),
                   let window = (Windows.list.first { $0.cgWindowId == id }) {
                    window.focus()
                    output = noOutput
                    return
                }
            }
            output = error
        }
        return output
    }
}

struct JsonOutput: Codable {
    var windows: [JsonWindow]
}

struct JsonWindow: Codable {
    var id: CGWindowID?
    var title: String
}

class CliClient {
    static func detectCommand() -> String? {
        let args = CommandLine.arguments
        if args.count == 2 && !args[1].starts(with: "--logs=") {
            if args[1] == "--list" || args[1].hasPrefix("--focus=") {
                return args[1]
            }
        }
        return nil
    }

    static func sendCommandAndProcessResponse(_ command: String) {
        do {
            let serverPortClient = try CFMessagePortCreateRemote(nil, CliEvents.portName as CFString).unwrapOrThrow()
            let data = try command.data(using: .utf8).unwrapOrThrow()
            var returnData: Unmanaged<CFData>?
            let _ = CFMessagePortSendRequest(serverPortClient, 0, data as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &returnData)
            let responseData = try returnData.unwrapOrThrow().takeRetainedValue()
            if let response = String(data: responseData as Data, encoding: .utf8) {
                if response != "\"\(CliServer.error)\"" {
                    if response != "\"\(CliServer.noOutput)\"" {
                        print(response)
                    }
                    exit(0)
                }
            }
            print("Couldn't execute command. Is it correct?")
            exit(1)
        } catch {
            print("AltTab.app needs to be running for CLI commands to work")
            exit(1)
        }
    }
}
