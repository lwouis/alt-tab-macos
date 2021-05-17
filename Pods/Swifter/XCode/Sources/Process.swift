//
//  Process
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

public class Process {

    public static var pid: Int {
        return Int(getpid())
    }

    public static var tid: UInt64 {
        #if os(Linux)
            return UInt64(pthread_self())
        #else
            var tid: __uint64_t = 0
            pthread_threadid_np(nil, &tid)
            return UInt64(tid)
        #endif
    }

    private static var signalsWatchers = [(Int32) -> Void]()
    private static var signalsObserved = false

    public static func watchSignals(_ callback: @escaping (Int32) -> Void) {
        if !signalsObserved {
            [SIGTERM, SIGHUP, SIGSTOP, SIGINT].forEach { item in
                signal(item) { signum in
                    Process.signalsWatchers.forEach { $0(signum) }
                }
            }
            signalsObserved = true
        }
        signalsWatchers.append(callback)
    }
}
