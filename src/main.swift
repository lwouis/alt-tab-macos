import AppKit
import Darwin

if let command = CliClient.detectCommand() {
    CliClient.sendCommandAndProcessResponse(command)
}

// - if the app is quit/force-quit from Activity Monitor, it will receive SIGTERM and applicationWillTerminate won't be called
// - if the app crashes in swift code (e.g. unexpected nil object), SIGTRAP is sent
// we intercept these signals, and do an emergency exit
[SIGTERM, SIGTRAP].forEach {
    signal($0) { s in
        emergencyExit("Exiting after receiving signal", s)
    }
}

// - if the app crashes in objective-c code, an NSException may be sent
// we intercept the exception, and do an emergency exit
NSSetUncaughtExceptionHandler { (exception) in
    emergencyExit("Exiting after receiving uncaught NSException", exception)
}

App.shared.run()

func printStackTrace() {
    let stackSymbols = Thread.callStackSymbols
    for symbol in stackSymbols {
        print(symbol)
    }
}

// during an emergency exit, we re-enable the native command+tab, and log
fileprivate func emergencyExit(_ logs: Any?...) {
    setNativeCommandTabEnabled(true)
    print(logs)
    printStackTrace()
    exit(0)
}
