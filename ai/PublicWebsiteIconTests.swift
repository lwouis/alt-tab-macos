import Foundation

@main struct PublicWebsiteIconTests {
    static func main() {
        precondition(!FixtureIconResolver.laboratory)
        for raw in ["https://darioamodei.com/post/example?q=private#section", "http://www.google.com/search?q=private", "https://news.example.org/article"] {
            let page = FixtureIconResolver.pageForDocument(URL(string: raw)!)!
            precondition(page.scheme == "https" && page.path == "/" && page.query == nil && page.fragment == nil)
        }
        for raw in ["http://example.org/icon.png", "https://localhost/", "https://host.local/", "https://host.home.arpa/", "https://127.0.0.1/", "https://2130706433/", "https://[::1]/", "https://user:pass@example.org/", "https://example.org:8443/", "file:///tmp/a"] {
            precondition(!FixtureIconResolver.allowed(URL(string: raw)!))
        }
        for address: [UInt8] in [[127,0,0,1], [10,1,1,1], [192,168,1,1], [169,254,1,1], [100,64,0,1], [172,16,0,1], [224,0,0,1]] {
            precondition(!FixtureIconResolver.publicAddress(address))
        }
        precondition(FixtureIconResolver.publicAddress([8,8,8,8]))
        precondition(!FixtureIconResolver.publicAddress(Array(repeating: 0, count: 16)))
        let page = URL(string: "https://www.example.org/")!
        let html = Data("<html><head><base href='https://cdn.example.org/assets/'><link rel='icon' href='a.png'><link rel='icon' href='a.png'><link rel='apple-touch-icon' href='b.png'><link rel='icon' href='https://127.0.0.1/icon'></head></html>".utf8)
        precondition(FixtureIconResolver.candidates(html, page: page).map(\.absoluteString) == ["https://cdn.example.org/assets/a.png", "https://cdn.example.org/assets/b.png", "https://www.example.org/favicon.ico"])
        print("PASS: general homepage mapping, local URL/address rejection, base URL, touch icon and duplicate handling")
        for raw in CommandLine.arguments.dropFirst() {
            let page = FixtureIconResolver.pageForDocument(URL(string: raw)!)!
            let done = DispatchSemaphore(value: 0)
            FixtureIconResolver.resolveArtwork(page) { artwork in
                print("\(page.host!): \(artwork == nil ? "no usable artwork" : "64px artwork")")
                precondition(artwork != nil, "Expected public-site artwork")
                done.signal()
            }
            precondition(done.wait(timeout: .now() + 45) == .success)
        }
    }
}
