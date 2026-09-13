import Foundation
@main struct Tests {
    static func main() {
        let root = URL(string: "http://127.0.0.1:18769/")!
        precondition(FixtureIconResolver.allowed(root))
        for raw in ["https://example.com/", "file:///tmp/icon", "http://127.0.0.1:80/", "http://user:pass@127.0.0.1:18769/"] {
            precondition(!FixtureIconResolver.allowed(URL(string: raw)!))
        }
        let html = Data("<html><head><link rel='ICON' href='native-red.png'><link rel='icon' href='https://example.com/icon.png'></head></html>".utf8)
        let candidates = FixtureIconResolver.candidates(html, page: root)
        precondition(candidates.map(\.lastPathComponent) == ["native-red.png", "favicon.ico"])
        precondition(FixtureIconResolver.image(Data("not an image".utf8)) == nil)
        var images: [Data] = []
        for name in ["native-red.html", "native-blue.html", "missing.html"] {
            let done = DispatchSemaphore(value: 0)
            let start = ProcessInfo.processInfo.systemUptime
            FixtureIconResolver.resolve(root.appendingPathComponent(name)) { data in
                if name == "missing.html" { precondition(data == nil) }
                else {
                    precondition(data != nil)
                    let image = FixtureIconResolver.image(data!)!
                    precondition(image.width == 64 && image.height == 64)
                    images.append(data!)
                }
                print("\(name): bytes=\(data?.count ?? 0), milliseconds=\(Int((ProcessInfo.processInfo.systemUptime - start) * 1000))")
                done.signal()
            }
            precondition(done.wait(timeout: .now() + 15) == .success)
        }
        precondition(images.count == 2 && images[0] != images[1])
        print("PASS: origin restrictions, candidate selection, image validation, two distinct icons, missing icon")
    }
}
