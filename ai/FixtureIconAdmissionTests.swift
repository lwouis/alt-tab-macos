import Foundation

@main struct AdmissionTests {
    static func main() {
        let root = URL(string: "http://127.0.0.1:18769/slow.html")!
        let group = DispatchGroup()
        let lock = NSLock()
        var completed = 0
        var accepted = 0
        for index in 0..<1000 {
            group.enter()
            FixtureIconResolver.resolveArtwork(URL(string: "?request=\(index)", relativeTo: root)!) { artwork in
                lock.lock()
                completed += 1
                if artwork != nil { accepted += 1 }
                lock.unlock()
                group.leave()
            }
        }
        precondition(group.wait(timeout: .now() + 30) == .success)
        precondition(completed == 1000 && accepted > 0 && accepted <= 32)
        print("PASS: completed \(completed) callers, admitted \(accepted) unique slow pages within the 32-page budget")
        let recovered = DispatchSemaphore(value: 0)
        FixtureIconResolver.resolveArtwork(root) { artwork in
            precondition(artwork != nil, "Admission overload must not poison subsequent requests")
            recovered.signal()
        }
        precondition(recovered.wait(timeout: .now() + 10) == .success)
        print("PASS: resolver recovers after overload")
    }
}
