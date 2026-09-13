import Foundation
import CoreGraphics
import Darwin

/// Finds a website's icon through its public homepage. Requests never carry the browser's cookies, credentials, or the
/// document's path, query or fragment.
enum WebsiteIconResolver {
    private struct Entry {
        let image: CGImage?
        let expires: Date
    }
    private static let queue = DispatchQueue(label: "website-icon-resolver", qos: .utility)
    private static var pages: [URL: Entry] = [:]
    private static var pendingPages: [URL: [(CGImage?) -> Void]] = [:]
    private static var assets: [URL: Entry] = [:]
    private static var pendingAssets: [URL: [(CGImage?) -> Void]] = [:]
    private static var generation = 0

    /// `http` documents look up the `https` homepage: icons are never fetched in cleartext.
    static func homepage(for document: URL) -> URL? {
        guard document.user == nil, document.password == nil, ["https", "http"].contains(document.scheme ?? ""),
              var parts = URLComponents(url: document, resolvingAgainstBaseURL: true) else { return nil }
        parts.scheme = "https"
        if parts.port == 80 { parts.port = nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        guard let page = parts.url, isPublic(page) else { return nil }
        return page
    }

    /// Names only; addresses are screened after DNS resolution by `resolvesToPublicAddresses`.
    static func isPublic(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 8192, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              host.count <= 253, host.contains("."), !host.hasSuffix("."),
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              host.split(separator: ".").last?.contains(where: { $0.isLetter }) == true else { return false }
        return !["local", "localhost", "internal", "invalid", "test", "example", "onion", "home.arpa"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    /// Rejects unspecified, private, loopback, link-local, CGNAT, multicast, benchmarking, documentation and relay ranges.
    static func isPublicAddress(_ bytes: [UInt8]) -> Bool {
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

    /// Blocking: `getaddrinfo` can't be cancelled, so callers run it on a bounded background queue. Every address must be
    /// public, including redirect and CDN hosts. This is not transport pinning.
    static func resolvesToPublicAddresses(_ url: URL) -> Bool {
        guard isPublic(url), let host = url.host else { return false }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var addresses: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &addresses) == 0, let first = addresses else { return false }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            guard let bytes = addressBytes(entry.pointee), isPublicAddress(bytes) else { return false }
            current = entry.pointee.ai_next
        }
        return true
    }

    private static func addressBytes(_ info: addrinfo) -> [UInt8]? {
        if info.ai_family == AF_INET {
            var address = UnsafeRawPointer(info.ai_addr).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            return withUnsafeBytes(of: &address) { Array($0) }
        }
        guard info.ai_family == AF_INET6 else { return nil }
        var address = UnsafeRawPointer(info.ai_addr).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    /// Declared `icon` and `apple-touch-icon` links in document order (at most 8, honoring `<base href>`), then `/favicon.ico`.
    static func candidates(in html: Data, page: URL) -> [URL] {
        guard html.count <= 1_048_576,
              let document = try? XMLDocument(data: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let nodes = try? document.nodes(forXPath: "//link") else { return [] }
        let base = (try? document.nodes(forXPath: "//base[@href]").first as? XMLElement)?.attribute(forName: "href")?.stringValue
            .flatMap { URL(string: $0, relativeTo: page)?.absoluteURL } ?? page
        let links = nodes.compactMap { node -> URL? in
            guard let element = node as? XMLElement,
                  let rel = element.attribute(forName: "rel")?.stringValue?.lowercased().split(whereSeparator: { $0.isWhitespace }),
                  rel.contains("icon") || rel.contains("apple-touch-icon"), let href = element.attribute(forName: "href")?.stringValue,
                  let url = URL(string: href, relativeTo: base)?.absoluteURL, isPublic(url) else { return nil }
            return url
        }
        var seen = Set<URL>()
        return (Array(links.prefix(8)) + [URL(string: "/favicon.ico", relativeTo: page)!.absoluteURL]).filter { seen.insert($0).inserted }
    }

    /// Completes on a background queue. Concurrent requests for a page or an asset share one transfer and one decode.
    static func resolve(_ page: URL, _ completion: @escaping (CGImage?) -> Void) {
        queue.async {
            guard isPublic(page), page.path.isEmpty || page.path == "/", page.query == nil, page.fragment == nil else { completion(nil); return }
            if let entry = pages[page], entry.expires > Date() { completion(entry.image); return }
            guard let start = join(&pendingPages, page, completion) else { completion(nil); return }
            guard start else { return }
            fetch(page, untilHeadEnds: true) { html, finalURL in
                let urls = html.map { candidates(in: $0, page: finalURL) } ?? [page.appendingPathComponent("favicon.ico")]
                firstImage(urls) { image in complete(&pages, &pendingPages, page, image).forEach { $0(image) } }
            }
        }
    }

    /// Turning the feature off completes pending callers with no image and discards late results.
    static func reset() {
        queue.async {
            generation += 1
            let callbacks = pendingPages.values.flatMap { $0 }
            pendingPages.removeAll()
            pendingAssets.removeAll()
            pages.removeAll()
            assets.removeAll()
            WebsiteIconTransfer.shared.cancelAll()
            callbacks.forEach { $0(nil) }
        }
    }

    /// True when the caller must start the work, false when it joined work in flight, nil when over capacity (the caller
    /// completes without an image and can retry on a later summon). Callbacks never run here: they can re-enter the
    /// resolver, which would overlap Swift's exclusive access to the `inout` dictionary.
    private static func join(_ pending: inout [URL: [(CGImage?) -> Void]], _ key: URL, _ completion: @escaping (CGImage?) -> Void) -> Bool? {
        if pending[key] != nil {
            guard pending[key]!.count < 256 else { return nil }
            pending[key]!.append(completion)
            return false
        }
        guard pending.count < 32 else { return nil }
        pending[key] = [completion]
        return true
    }

    /// Returns the waiting callbacks for the caller to run once exclusive access has ended.
    private static func complete(_ cache: inout [URL: Entry], _ pending: inout [URL: [(CGImage?) -> Void]], _ key: URL, _ image: CGImage?) -> [(CGImage?) -> Void] {
        cache = cache.filter { $0.value.expires > Date() }
        if cache.count >= 32, let oldest = cache.min(by: { $0.value.expires < $1.value.expires }) { cache.removeValue(forKey: oldest.key) }
        cache[key] = Entry(image: image, expires: Date().addingTimeInterval(image == nil ? 5 : 30))
        return pending.removeValue(forKey: key) ?? []
    }

    private static func firstImage(_ urls: [URL], _ completion: @escaping (CGImage?) -> Void) {
        guard let first = urls.first else { completion(nil); return }
        asset(first) { image in
            guard image == nil else { completion(image); return }
            firstImage(Array(urls.dropFirst()), completion)
        }
    }

    private static func asset(_ url: URL, _ completion: @escaping (CGImage?) -> Void) {
        if let entry = assets[url], entry.expires > Date() { completion(entry.image); return }
        guard let start = join(&pendingAssets, url, completion) else { completion(nil); return }
        guard start else { return }
        fetch(url) { data, _ in
            let image = data.flatMap { WebsiteIconRenderer.render([$0]) }
            complete(&assets, &pendingAssets, url, image).forEach { $0(image) }
        }
    }

    private static func fetch(_ url: URL, untilHeadEnds: Bool = false, _ completion: @escaping (Data?, URL) -> Void) {
        let epoch = generation
        WebsiteIconTransfer.shared.fetch(url, untilHeadEnds: untilHeadEnds) { data, finalURL in
            queue.async {
                guard epoch == generation else { return }
                completion(data, finalURL)
            }
        }
    }
}

/// One ephemeral session streams into capped buffers. At most 8 transfers run and 32 wait; oversized responses,
/// non-public redirects and more than 3 redirects are cancelled.
private final class WebsiteIconTransfer: NSObject, URLSessionDataDelegate {
    static let shared = WebsiteIconTransfer()
    private struct Transfer {
        var data = Data()
        var url: URL
        var valid = false
        var reachedHeadEnd = false
        let untilHeadEnds: Bool
        var redirects = 0
        let completion: (Data?, URL) -> Void
    }
    private struct Waiting {
        let url: URL
        let untilHeadEnds: Bool
        let completion: (Data?, URL) -> Void
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var waiting: [Waiting] = []
    private let limit = 1_048_576
    private let addressQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8
        queue.qualityOfService = .utility
        return queue
    }()
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

    func fetch(_ url: URL, untilHeadEnds: Bool, _ completion: @escaping (Data?, URL) -> Void) {
        guard WebsiteIconResolver.isPublic(url) else { completion(nil, url); return }
        lock.lock()
        guard transfers.count < 8 else {
            let queued = waiting.count < 32
            if queued { waiting.append(Waiting(url: url, untilHeadEnds: untilHeadEnds, completion: completion)) }
            lock.unlock()
            if !queued { completion(nil, url) }
            return
        }
        let task = session.dataTask(with: url)
        transfers[task.taskIdentifier] = Transfer(url: url, untilHeadEnds: untilHeadEnds, completion: completion)
        lock.unlock()
        addressQueue.addOperation {
            guard WebsiteIconResolver.resolvesToPublicAddresses(url) else { task.cancel(); return }
            task.resume()
        }
    }

    func cancelAll() {
        lock.lock()
        waiting.removeAll()
        let ids = Set(transfers.keys)
        lock.unlock()
        session.getAllTasks { tasks in tasks.filter { ids.contains($0.taskIdentifier) }.forEach { $0.cancel() } }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let untilHeadEnds = transfers[dataTask.taskIdentifier]?.untilHeadEnds == true
        let valid = (response as? HTTPURLResponse)?.statusCode == 200 && response.url.map(WebsiteIconResolver.isPublic) == true
            && (untilHeadEnds || response.expectedContentLength <= limit)
        transfers[dataTask.taskIdentifier]?.valid = valid
        if let url = response.url { transfers[dataTask.taskIdentifier]?.url = url }
        lock.unlock()
        completionHandler(valid ? .allow : .cancel)
    }

    /// HTML downloads stop at `</head>`: icon links never need the page body.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let id = dataTask.taskIdentifier
        let overflow = (transfers[id]?.data.count ?? limit) + data.count > limit
        if !overflow {
            transfers[id]?.data.append(data)
            if let transfer = transfers[id], transfer.untilHeadEnds, let text = String(data: transfer.data, encoding: .utf8),
               let end = text.range(of: "</head>", options: .caseInsensitive) {
                transfers[id]?.data = Data(text[..<end.upperBound].utf8)
                transfers[id]?.reachedHeadEnd = true
            }
        }
        let reachedHeadEnd = transfers[id]?.reachedHeadEnd == true
        lock.unlock()
        if overflow || reachedHeadEnd { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        let next = waiting.isEmpty ? nil : waiting.removeFirst()
        lock.unlock()
        if let next { fetch(next.url, untilHeadEnds: next.untilHeadEnds, next.completion) }
        guard let transfer else { return }
        transfer.completion((error == nil || transfer.reachedHeadEnd) && transfer.valid ? transfer.data : nil, transfer.url)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        transfers[task.taskIdentifier]?.redirects += 1
        let count = transfers[task.taskIdentifier]?.redirects ?? 4
        lock.unlock()
        guard count <= 3, let url = request.url, WebsiteIconResolver.isPublic(url) else { completionHandler(nil); return }
        addressQueue.addOperation {
            completionHandler(WebsiteIconResolver.resolvesToPublicAddresses(url) ? request : nil)
        }
    }
}
