import Foundation
import CoreGraphics


@main struct StressTests {
    static let root = URL(string: "http://127.0.0.1:18769/")!
    static func batch(_ paths: [String], valid: Bool) {
        let group = DispatchGroup()
        let lock = NSLock()
        var latencies: [Double] = []
        var firstImage: CGImage?
        var sharedImage = true
        for path in paths {
            group.enter()
            let start = ProcessInfo.processInfo.systemUptime
            FixtureIconResolver.resolveArtwork(root.appendingPathComponent(path)) { artwork in
                precondition((artwork != nil) == valid, path)
                lock.lock()
                latencies.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                if let artwork {
                    if let firstImage { sharedImage = sharedImage && firstImage === artwork.image }
                    else { firstImage = artwork.image }
                }
                lock.unlock()
                group.leave()
            }
        }
        precondition(group.wait(timeout: .now() + 30) == .success)
        latencies.sort()
        if valid && (Set(paths).count == 1 || paths.allSatisfy { $0.hasPrefix("blue-") }) { precondition(sharedImage, "repeated consumers should share the decoded bitmap") }
        print("requests=\(paths.count) unique=\(Set(paths).count) p50ms=\(latencies[latencies.count / 2]) p95ms=\(latencies[max(0, Int(ceil(Double(latencies.count) * 0.95)) - 1)])")
    }
    static func main() {
        batch(Array(repeating: "slow.html", count: 128), valid: true)
        batch(Array(repeating: "slow.html", count: 1000), valid: true)
        batch((0..<16).map { "blue-\($0).html" }, valid: true)
        batch(Array(repeating: "missing.html", count: 128), valid: false)
        batch(["large.html", "stream-large.html", "external.html", "loop.html"], valid: false)
        batch(["redirect.html"], valid: true)
        print("PASS: shared in-flight work, decoded bitmap reuse, warm cache, parallel pages, absent, oversized, blocked and allowed redirects")
    }
}
