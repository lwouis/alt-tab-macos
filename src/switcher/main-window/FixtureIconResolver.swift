import Foundation
import ImageIO

/// Restricted experiment: loopback fixtures or explicitly reviewed public URLs, without browser credentials or extensions.
final class FixtureIconResolver: NSObject, URLSessionTaskDelegate {
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
        (url.scheme == "http" && url.host == "127.0.0.1" && url.port == 18769 && url.user == nil && url.password == nil)
            || listed(url, "ALTTAB_NATIVE_ICON_TEST_PAGES")
    }
    /// Use a reviewed public homepage without forwarding document paths or query data.
    static func pageForDocument(_ url: URL) -> URL? {
        guard url.user == nil, url.password == nil else { return nil }
        if url.scheme == "http", url.host == "127.0.0.1", url.port == 18769 { return url }
        guard url.scheme == "https", var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        guard let page = parts.url, listed(page, "ALTTAB_NATIVE_ICON_TEST_PAGES") else { return nil }
        return page
    }
    static func allowed(_ url: URL) -> Bool {
        allowedPage(url) || listed(url, "ALTTAB_NATIVE_ICON_TEST_ASSETS")
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
        let links = nodes.compactMap { node -> URL? in
            guard let element = node as? XMLElement,
                  let rel = element.attribute(forName: "rel")?.stringValue?.lowercased().split(whereSeparator: { $0.isWhitespace }),
                  rel.contains("icon"), let href = element.attribute(forName: "href")?.stringValue,
                  let url = URL(string: href, relativeTo: page)?.absoluteURL, allowed(url) else { return nil }
            return url
        }
        return Array(links.prefix(8)) + [URL(string: "/favicon.ico", relativeTo: page)!.absoluteURL]
    }
    private static func fetch(_ url: URL, headOnly: Bool = false, _ completion: @escaping (Data?, URL) -> Void) {
        FixtureTransfer.shared.fetch(url, headOnly: headOnly, completion)
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
                guard let data else { complete(page, nil); return }
                next(candidates(data, page: finalURL)) { complete(page, $0) }
            }
        }
    }
    private static func complete(_ page: URL, _ artwork: Artwork?) {
        queue.async {
            cache = cache.filter { $0.value.expires > Date() }
            if cache.count >= 32, let oldest = cache.min(by: { $0.value.expires < $1.value.expires }) { cache.removeValue(forKey: oldest.key) }
            cache[page] = Entry(artwork: artwork, expires: Date().addingTimeInterval(artwork == nil ? 5 : 30))
            let callbacks = pending.removeValue(forKey: page) ?? []
            callbacks.forEach { $0(artwork) }
        }
    }
    private static func next(_ urls: [URL], _ completion: @escaping (Artwork?) -> Void) {
        guard let first = urls.first else { completion(nil); return }
        sharedImage(first) { artwork in
            if let artwork { completion(artwork) }
            else { next(Array(urls.dropFirst()), completion) }
        }
    }
    private static func sharedImage(_ url: URL, _ completion: @escaping (Artwork?) -> Void) {
        queue.async {
            if let entry = images[url], entry.expires > Date() { completion(entry.artwork); return }
            if pendingImages[url] != nil {
                guard pendingImages[url]!.count < 256 else { completion(nil); return }
                pendingImages[url]!.append(completion)
                return
            }
            guard pendingImages.count < 32 else { completion(nil); return }
            pendingImages[url] = [completion]
            fetch(url) { data, _ in
                queue.async {
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
        task.resume()
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
        completionHandler(count <= 3 && request.url.map(FixtureIconResolver.allowed) == true ? request : nil)
    }
}
