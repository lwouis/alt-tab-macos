import Foundation
import ImageIO
import Darwin

/// Homepage icon discovery without browser credentials; test launches retain a restricted URL policy.
final class FixtureIconResolver: NSObject, URLSessionTaskDelegate {
    static var laboratory: Bool { ProcessInfo.processInfo.environment["ALTTAB_NATIVE_ICON_PROTOTYPE"] == "1" }
    static func publicURL(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 8192, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              host.count <= 253, host.contains("."), !host.hasSuffix("."),
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              host.split(separator: ".").last?.contains(where: { $0.isLetter }) == true else { return false }
        return !["local", "localhost", "internal", "invalid", "test", "example", "onion", "home.arpa"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }
    /// Screen every resolved address, including redirect/CDN hosts, before URLSession starts it.
    static func publicAddress(_ bytes: [UInt8]) -> Bool {
        if bytes.count == 4 {
            let a = bytes[0], b = bytes[1], c = bytes[2]
            return a != 0 && a != 10 && a != 127 && a < 224
                && !(a == 100 && (64...127).contains(b)) && !(a == 169 && b == 254)
                && !(a == 172 && (16...31).contains(b)) && !(a == 192 && (b == 168 || b == 0 || (b == 88 && c == 99)))
                && !(a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100)))
                && !(a == 203 && b == 0 && c == 113)
        }
        return bytes.count == 16 && bytes[0] & 0xe0 == 0x20
            && !(bytes[0] == 0x20 && bytes[1] == 0x01 && (bytes[2] < 2 || (bytes[2] == 0x0d && bytes[3] == 0xb8)))
            && !(bytes[0] == 0x20 && bytes[1] == 0x02)
    }
    static func publicDestination(_ url: URL) -> Bool {
        guard publicURL(url), let host = url.host else { return false }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var addresses: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &addresses) == 0, let first = addresses else { return false }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            let value = entry.pointee
            let bytes: [UInt8]
            if value.ai_family == AF_INET {
                var address = UnsafeRawPointer(value.ai_addr).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                bytes = withUnsafeBytes(of: &address) { Array($0) }
            } else if value.ai_family == AF_INET6 {
                var address = UnsafeRawPointer(value.ai_addr).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                bytes = withUnsafeBytes(of: &address) { Array($0) }
            } else { return false }
            guard publicAddress(bytes) else { return false }
            current = value.ai_next
        }
        return true
    }
    private static func canonical(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return "" }
        parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        return parts.string ?? ""
    }
    private static func listed(_ url: URL, _ key: String) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil else { return false }
        return (ProcessInfo.processInfo.environment[key] ?? "").split(separator: "|")
            .compactMap { URL(string: String($0)) }.contains { canonical($0) == canonical(url) }
    }
    static func allowedPage(_ url: URL) -> Bool {
        if !laboratory { return publicURL(url) && (url.path.isEmpty || url.path == "/") && url.query == nil && url.fragment == nil }
        return (url.scheme == "http" && url.host == "127.0.0.1" && url.port == 18769 && url.user == nil && url.password == nil)
            || listed(url, "ALTTAB_NATIVE_ICON_TEST_PAGES")
    }
    /// Use a reviewed public homepage without forwarding document paths or query data.
    static func pageForDocument(_ url: URL) -> URL? {
        guard url.user == nil, url.password == nil else { return nil }
        if laboratory, url.scheme == "http", url.host == "127.0.0.1", url.port == 18769 { return url }
        if laboratory && url.scheme != "https" { return nil }
        guard ["https", "http"].contains(url.scheme ?? ""), var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        parts.scheme = "https"
        if parts.port == 80 { parts.port = nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        guard let page = parts.url, laboratory ? listed(page, "ALTTAB_NATIVE_ICON_TEST_PAGES") : publicURL(page) else { return nil }
        return page
    }
    static func allowed(_ url: URL) -> Bool {
        laboratory ? (allowedPage(url) || listed(url, "ALTTAB_NATIVE_ICON_TEST_ASSETS")) : publicURL(url)
    }
    struct Artwork {
        let data: Data
        let image: CGImage
    }
    private struct Entry {
        let artwork: Artwork?
        let expires: Date
    }
    private static let queue = DispatchQueue(label: "local.fixture-icon-cache", qos: .utility)
    private static var cache: [URL: Entry] = [:]
    private static var pending: [URL: [(Artwork?) -> Void]] = [:]
    private static var images: [URL: Entry] = [:]
    private static var pendingImages: [URL: [(Artwork?) -> Void]] = [:]
    static func image(_ data: Data) -> CGImage? {
        guard data.count <= 1_048_576, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 512, height <= 512 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    static func candidates(_ data: Data, page: URL) -> [URL] {
        guard data.count <= 1_048_576,
              let doc = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let nodes = try? doc.nodes(forXPath: "//link") else { return [] }
        let base = (try? doc.nodes(forXPath: "//base[@href]").first as? XMLElement)?.attribute(forName: "href")?.stringValue
            .flatMap { URL(string: $0, relativeTo: page)?.absoluteURL } ?? page
        let links = nodes.compactMap { node -> URL? in
            guard let element = node as? XMLElement,
                  let rel = element.attribute(forName: "rel")?.stringValue?.lowercased().split(whereSeparator: { $0.isWhitespace }),
                  (rel.contains("icon") || rel.contains("apple-touch-icon")), let href = element.attribute(forName: "href")?.stringValue,
                  let url = URL(string: href, relativeTo: base)?.absoluteURL, allowed(url) else { return nil }
            return url
        }
        var seen = Set<URL>()
        return (Array(links.prefix(8)) + [URL(string: "/favicon.ico", relativeTo: page)!.absoluteURL]).filter { seen.insert($0).inserted }
    }
    private static var generation = 0
    static func reset() {
        queue.async {
            generation += 1
            let callbacks = pending.values.flatMap { $0 }
            pending.removeAll()
            pendingImages.removeAll()
            cache.removeAll()
            images.removeAll()
            FixtureTransfer.shared.cancelAll()
            callbacks.forEach { $0(nil) }
        }
    }
    private static func fetch(_ url: URL, headOnly: Bool = false, _ completion: @escaping (Data?, URL) -> Void) {
        let epoch = generation
        FixtureTransfer.shared.fetch(url, headOnly: headOnly) { data, finalURL in
            queue.async {
                guard epoch == generation else { return }
                completion(data, finalURL)
            }
        }
    }
    static func resolve(_ page: URL, completion: @escaping (Data?) -> Void) {
        resolveArtwork(page) { completion($0?.data) }
    }
    static func resolveArtwork(_ page: URL, completion: @escaping (Artwork?) -> Void) {
        queue.async {
            guard allowedPage(page) else { completion(nil); return }
            if let entry = cache[page], entry.expires > Date() { completion(entry.artwork); return }
            if pending[page] != nil {
                guard pending[page]!.count < 256 else { completion(nil); return }
                pending[page]!.append(completion)
                return
            }
            guard pending.count < 32 else { completion(nil); return }
            pending[page] = [completion]
            fetch(page, headOnly: true) { data, finalURL in
                guard let data else { next([page.appendingPathComponent("favicon.ico")]) { complete(page, $0) }; return }
                next(candidates(data, page: finalURL)) { complete(page, $0) }
            }
        }
    }
    private static func complete(_ page: URL, _ artwork: Artwork?) {
        cache = cache.filter { $0.value.expires > Date() }
        if cache.count >= 32, let oldest = cache.min(by: { $0.value.expires < $1.value.expires }) { cache.removeValue(forKey: oldest.key) }
        cache[page] = Entry(artwork: artwork, expires: Date().addingTimeInterval(artwork == nil ? 5 : 30))
        let callbacks = pending.removeValue(forKey: page) ?? []
        callbacks.forEach { $0(artwork) }
    }
    private static func next(_ urls: [URL], _ completion: @escaping (Artwork?) -> Void) {
        guard let first = urls.first else { completion(nil); return }
        sharedImage(first) { artwork in
            if let artwork { completion(artwork) }
            else { next(Array(urls.dropFirst()), completion) }
        }
    }
    private static func sharedImage(_ url: URL, _ completion: @escaping (Artwork?) -> Void) {
        if let entry = images[url], entry.expires > Date() { completion(entry.artwork); return }
        if pendingImages[url] != nil {
            guard pendingImages[url]!.count < 256 else { completion(nil); return }
            pendingImages[url]!.append(completion)
            return
        }
        guard pendingImages.count < 32 else { completion(nil); return }
        pendingImages[url] = [completion]
        fetch(url) { data, _ in
            let artwork = data.flatMap { data -> Artwork? in
                guard image(data) != nil,
                      let rendered = IconRenderer.render([["data": data.base64EncodedString()]]),
                      let png = Data(base64Encoded: rendered.png), let bitmap = image(png) else { return nil }
                return Artwork(data: png, image: bitmap)
            }
            images = images.filter { $0.value.expires > Date() }
            if images.count >= 32, let oldest = images.min(by: { $0.value.expires < $1.value.expires }) { images.removeValue(forKey: oldest.key) }
            images[url] = Entry(artwork: artwork, expires: Date().addingTimeInterval(artwork == nil ? 5 : 30))
            let callbacks = pendingImages.removeValue(forKey: url) ?? []
            callbacks.forEach { $0(artwork) }
        }
    }

}

/// A shared session streams into a capped buffer; oversized and off-origin responses are cancelled.
private final class FixtureTransfer: NSObject, URLSessionDataDelegate {
    static let shared = FixtureTransfer()
    private struct Transfer {
        var data = Data()
        var url: URL
        var valid = false
        var completedHead = false
        let headOnly: Bool
        var redirects = 0
        let completion: (Data?, URL) -> Void
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private struct Waiting {
        let url: URL
        let headOnly: Bool
        let completion: (Data?, URL) -> Void
    }
    private var waiting: [Waiting] = []
    private let limit = 1_048_576
    private let destinationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8
        queue.qualityOfService = .utility
        return queue
    }()
    func cancelAll() {
        lock.lock()
        waiting.removeAll()
        let ids = Set(transfers.keys)
        lock.unlock()
        session.getAllTasks { tasks in tasks.filter { ids.contains($0.taskIdentifier) }.forEach { $0.cancel() } }
    }
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 4
        config.httpMaximumConnectionsPerHost = 4
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()
    func fetch(_ url: URL, headOnly: Bool, _ completion: @escaping (Data?, URL) -> Void) {
        guard FixtureIconResolver.allowed(url) else { completion(nil, url); return }
        lock.lock()
        if transfers.count >= 8 {
            guard waiting.count < 32 else { lock.unlock(); completion(nil, url); return }
            waiting.append(Waiting(url: url, headOnly: headOnly, completion: completion))
            lock.unlock()
            return
        }
        let task = session.dataTask(with: url)
        transfers[task.taskIdentifier] = Transfer(url: url, headOnly: headOnly, completion: completion)
        lock.unlock()
        destinationQueue.addOperation {
            guard FixtureIconResolver.laboratory || FixtureIconResolver.publicDestination(url) else {
                task.cancel()
                return
            }
            task.resume()
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let headOnly = transfers[dataTask.taskIdentifier]?.headOnly == true
        lock.unlock()
        let valid = (response as? HTTPURLResponse)?.statusCode == 200
            && response.url.map(FixtureIconResolver.allowed) == true && (headOnly || response.expectedContentLength <= limit)
        lock.lock()
        transfers[dataTask.taskIdentifier]?.valid = valid
        if let url = response.url { transfers[dataTask.taskIdentifier]?.url = url }
        lock.unlock()
        completionHandler(valid ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let overflow = (transfers[dataTask.taskIdentifier]?.data.count ?? limit) + data.count > limit
        if !overflow {
            transfers[dataTask.taskIdentifier]?.data.append(data)
            if let transfer = transfers[dataTask.taskIdentifier], transfer.headOnly,
               let text = String(data: transfer.data, encoding: .utf8),
               let end = text.range(of: "</head>", options: .caseInsensitive) {
                transfers[dataTask.taskIdentifier]?.data = Data(text[..<end.upperBound].utf8)
                transfers[dataTask.taskIdentifier]?.completedHead = true
            }
        }
        let completedHead = transfers[dataTask.taskIdentifier]?.completedHead == true
        lock.unlock()
        if overflow || completedHead { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        let next = waiting.isEmpty ? nil : waiting.removeFirst()
        lock.unlock()
        if let next { fetch(next.url, headOnly: next.headOnly, next.completion) }
        guard let transfer else { return }
        transfer.completion((error == nil || transfer.completedHead) && transfer.valid ? transfer.data : nil, transfer.url)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        transfers[task.taskIdentifier]?.redirects += 1
        let count = transfers[task.taskIdentifier]?.redirects ?? 4
        lock.unlock()
        guard count <= 3, let url = request.url, FixtureIconResolver.allowed(url) else { completionHandler(nil); return }
        destinationQueue.addOperation {
            completionHandler(FixtureIconResolver.laboratory || FixtureIconResolver.publicDestination(url) ? request : nil)
        }
    }
}
