import AppKit
import Darwin

if let command = CliClient.detectCommand() {
    CliClient.sendCommandAndProcessResponse(command)
}

// - SIGTRAP: if the app crashes in swift code (e.g. unexpected nil object), SIGTRAP is sent
// - SIGKILL: if we stop the app using SIGKILL (e.g. stopping from IntelliJ, or from the terminal), there is no chance to intercept it
//
// SIGTRAP keeps an in-handler exit because it is SYNCHRONOUS: the thread is stopped ON the trapping
// instruction, so ignoring it would re-run that instruction forever and a queued handler would never get a
// turn. The process is going down either way there, so the stack dump is worth the risk of running the
// handler.
signal(SIGTRAP) { s in
    emergencyExit("Exiting after receiving signal", s)
}
// - SIGTERM: if the app is quit/force-quit from Activity Monitor, it will receive SIGTERM and applicationWillTerminate won't be called
// - SIGINT/SIGHUP: if the app was launched from a terminal, ctrl-C reaches its whole process group and
//   closing the terminal sends a HUP. Both default to terminating us outright, which skips the capture
//   drain below and leaves macOS to ask the user for screen-recording consent, once per in-flight capture
//
// These three are ASYNCHRONOUS: they interrupt whatever thread happens to be running, so they are taken off
// the signal handler and onto a queue. Nothing `emergencyExit` does is async-signal-safe (it messages
// objects, allocates, logs), and a handler that runs while the interrupted thread holds the objc runtime's
// lock re-enters it: the process then dies with "BUG IN CLIENT OF LIBPLATFORM: Trying to recursively lock an
// os_unfair_lock", from inside `printStackTrace`. Measured over one QA pass: 76 quits, one of them aborted
// that way (2026-09-17 00:18:30), which reads as the app crashing on whatever was running at the time.
// `SIG_IGN` comes first, or the default action kills us before the source is ever dispatched.
let queuedSignals = [SIGTERM, SIGINT, SIGHUP]
// On its own queue rather than main: a quit must not wait on a main thread wedged inside a slow app's
// accessibility call, which is exactly when the capture drain matters most.
let signalQueue = DispatchQueue(label: "signals")
let signalSources = queuedSignals.map { s -> DispatchSourceSignal in
    signal(s, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: s, queue: signalQueue)
    source.setEventHandler { emergencyExit("Exiting after receiving signal", s) }
    source.resume()
    return source
}
// ...and UNBLOCK them, because a blocked signal is never delivered (neither to a handler nor to a dispatch
// source) and the mask is not ours to begin with: `posix_spawn` hands the child the signal mask of the
// thread that spawned it, so a launcher that spawns from a libdispatch worker (where signals are masked)
// starts AltTab unquittable. TERM, INT and HUP sit pending forever and only SIGKILL ends it, which is
// exactly the path that skips the capture drain below. Measured 2026-09-01, same binary and same pty either
// way: spawned from a blocked-mask parent it outlived every TERM; unblocked it exited in 0.26s.
var handledMask = sigset_t()
sigemptyset(&handledMask)
(queuedSignals + [SIGTRAP]).forEach { sigaddset(&handledMask, $0) }
pthread_sigmask(SIG_UNBLOCK, &handledMask, nil)

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
// note: _exit, not exit. exit runs atexit handlers and static destructors, which tear down
// framework state (e.g. mutexes) while other threads are still running. AppKit's event thread
// then crashes with 'mutex lock failed: Invalid argument'
fileprivate func emergencyExit(_ logs: Any?...) {
    setNativeCommandTabEnabled(true)
    print(logs)
    printStackTrace()
    makeSureAllCapturesAreFinished()
    StapledTicket.restoreBeforeExit()
    fflush(stdout)
    fflush(stderr)
    _exit(0)
}

func makeSureAllCapturesAreFinished() {
    App.isTerminating = true
    let timeout = 5.0
    let startTime = DispatchTime.now()
    var elapsedTime = 0.0
    while ActiveWindowCaptures.value() > 0 && elapsedTime <= timeout {
        Logger.warning { "There are \(ActiveWindowCaptures.value()) screenshots in progress. We need to wait for them to avoid a bug where macOS shows permission dialogs to the user for no reason." }
        Thread.sleep(forTimeInterval: 0.1)
        elapsedTime = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
    }
}
