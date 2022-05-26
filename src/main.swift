import AppKit
import Darwin

// if the app is quit/force-quit from Activity Monitor, it will receive SIGTERM and applicationWillTerminate won't be called
// we intercept SIGTERM so we can reset the native command-tab shortcut
signal(SIGTERM) { _ in
    // symbolic hotkeys state persist after the app is quit; we restore this shortcut before quitting
    setNativeCommandTabEnabled(true)
    exit(0)
}

App.shared.run()
