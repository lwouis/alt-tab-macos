import Foundation
@main struct RealWebsiteIconTests {
    static func main() {
        let pages = (ProcessInfo.processInfo.environment["ALTTAB_NATIVE_ICON_TEST_PAGES"] ?? "").split(separator: "|")
        precondition(!pages.isEmpty, "Supply the reviewed public test pages")
        precondition(!FixtureIconResolver.allowedPage(URL(string: "https://www.nrk.no/private?token=test")!))
        precondition(FixtureIconResolver.pageForDocument(URL(string: "https://not-reviewed.example/?client=safari")!) == nil)
        precondition(FixtureIconResolver.pageForDocument(URL(string: "https://www.google.com.evil.example/")!) == nil)
        precondition(FixtureIconResolver.pageForDocument(URL(string: "https://user:secret@www.google.com/")!) == nil)
        precondition(FixtureIconResolver.pageForDocument(URL(string: "https://www.google.com:8443/")!) == nil)
        precondition(FixtureIconResolver.pageForDocument(URL(string: "http://www.google.com/")!) == nil)
        for raw in pages {
            let url = URL(string: String(raw))!
            let variants = ["?client=safari", "?q=private-search#fragment", "article/example?token=secret"]
            for variant in variants {
                let document = URL(string: variant, relativeTo: url)!.absoluteURL
                precondition(FixtureIconResolver.pageForDocument(document) == url)
                precondition(!FixtureIconResolver.allowedPage(document), "Document URLs must not be fetchable")
            }
            let done = DispatchSemaphore(value: 0)
            let start = ProcessInfo.processInfo.systemUptime
            FixtureIconResolver.resolveArtwork(url) { artwork in
                precondition(artwork != nil, "No artwork returned for reviewed homepage: \(url.host!)")
                precondition(artwork?.image.width == 64 && artwork?.image.height == 64, "Expected normalized tile")
                print("\(url.host!): bitmap=\(artwork?.image.width ?? 0)x\(artwork?.image.height ?? 0) bytes=\(artwork?.data.count ?? 0) milliseconds=\(Int((ProcessInfo.processInfo.systemUptime - start) * 1000))")
                done.signal()
            }
            precondition(done.wait(timeout: .now() + 30) == .success)
        }
    }
}
