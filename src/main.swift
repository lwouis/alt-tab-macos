import AppKit
import Darwin

func printStackTrace() {
    let stackSymbols = Thread.callStackSymbols
    for symbol in stackSymbols {
        print(symbol)
    }
}

// - if the app is quit/force-quit from Activity Monitor, it will receive SIGTERM and applicationWillTerminate won't be called
// - if the app crashes in swift code (e.g. unexpected nil object), SIGTRAP is sent
// we intercept these signals, and reset the native command-tab shortcut
[SIGTERM, SIGTRAP].forEach {
    signal($0) { s in
        setNativeCommandTabEnabled(true)
        debugPrint("Exiting after receiving signal", s)
        printStackTrace()
        exit(0)
    }
}

// - if the app crashes in objective-c code, an NSException may be sent
// we intercept the exception, and reset the native command-tab shortcut
NSSetUncaughtExceptionHandler { (exception) in
    setNativeCommandTabEnabled(true)
    debugPrint("Exiting after receiving uncaught NSException", exception)
    printStackTrace()
    exit(0)
}

App.shared.run()
