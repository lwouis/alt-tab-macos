import Foundation

final class Search {
    static func normalizedQuery(_ query: String) -> String {
        SearchTestable.normalize(query).text
    }

    static func matches(_ window: Window, query: String) -> Bool {
        let normalized = normalizedQuery(query)
        if normalized.isEmpty { return true }
        ensureCache(for: window, normalizedQuery: normalized, originalQuery: query)
        return window.swBestSimilarity > 0
    }

    static func relevance(for window: Window, query: String) -> Double {
        let normalized = normalizedQuery(query)
        if normalized.isEmpty { return 0 }
        ensureCache(for: window, normalizedQuery: normalized, originalQuery: query)
        return window.swBestSimilarity
    }

    private static func ensureCache(for window: Window, normalizedQuery normalized: String, originalQuery: String) {
        let cacheKey = normalized + "|3"
        if window.lastSearchQuery == cacheKey { return }
        let appName = window.application.localizedName ?? ""
        let title = window.title
        let appResult = SearchTestable.tierMatch(query: originalQuery, text: appName)
        let titleResult = SearchTestable.tierMatch(query: originalQuery, text: title)
        window.swAppResults = appResult.map { [$0.toSWResult()] } ?? []
        window.swTitleResults = titleResult.map { [$0.toSWResult()] } ?? []
        let appScore = Double(appResult?.score ?? 0)
        let titleScore = Double(titleResult?.score ?? 0)
        window.swBestSimilarity = max(appScore * 1.02, titleScore)
        window.lastSearchQuery = cacheKey
    }
}

