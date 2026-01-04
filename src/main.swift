import AppKit
import Darwin

if let command = CliClient.detectCommand() {
    CliClient.sendCommandAndProcessResponse(command)
}

// - SIGTERM: if the app is quit/force-quit from Activity Monitor, it will receive SIGTERM and applicationWillTerminate won't be called
// - SIGTRAP: if the app crashes in swift code (e.g. unexpected nil object), SIGTRAP is sent
// - SIGKILL: if we stop the app using SIGKILL (e.g. stopping from IntelliJ, or from the terminal), there is no chance to intercept it
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
    makeSureAllCapturesAreFinished()
    exit(0)
}

func makeSureAllCapturesAreFinished() {
    App.app.isTerminating = true
    let timeout = 5.0
    let startTime = DispatchTime.now()
    var elapsedTime = 0.0
    while ActiveWindowCaptures.value() > 0 && elapsedTime <= timeout {
        Logger.warning { "There are \(ActiveWindowCaptures.value()) screenshots in progress. We need to wait for them to avoid a bug where macOS shows permission dialogs to the user for no reason." }
        Thread.sleep(forTimeInterval: 0.1)
        elapsedTime = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
    }
}
