import Darwin

class LightweightTimer {
    private static let timebaseRatio: Double = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    private let start: UInt64

    var elapsedMilliseconds: Double {
        let now = mach_absolute_time()
        let nanos = Double(now - start) * Self.timebaseRatio
        return nanos / 1_000_000 // ns → ms
    }

    init() {
        start = mach_absolute_time()
    }

    /// Returns true if the given number of milliseconds has passed
    func hasElapsed(milliseconds: Double) -> Bool {
        elapsedMilliseconds >= milliseconds
    }
}
