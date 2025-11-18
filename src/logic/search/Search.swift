import Foundation

/// Fuzzy search entry points used by Windows.
/// Encapsulates matching, relevance scoring, and per-window cache updates.
final class Search {
    static func matches(_ window: Window, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        ensureCache(for: window, query: trimmed)
        return !window.swAppResults.isEmpty || !window.swTitleResults.isEmpty
    }

    static func relevance(for window: Window, query: String) -> Double {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0.0 }
        ensureCache(for: window, query: trimmed)
        return window.swBestSimilarity
    }

    private static func ensureCache(for window: Window, query: String) {
        if window.lastSearchQuery == query { return }
        if query.isEmpty {
            window.lastSearchQuery = query
            window.swAppResults = []
            window.swTitleResults = []
            window.swBestSimilarity = 0
            return
        }
        let appName = window.application.localizedName ?? ""
        let title = window.title ?? ""
        let topK = 3
        let appResList = smithWatermanHighlights(query: query, text: appName, topK: topK, allowOverlaps: false)
        let titleResList = smithWatermanHighlights(query: query, text: title, topK: topK, allowOverlaps: false)
        window.swAppResults = appResList
        window.swTitleResults = titleResList
        let nameSim = appResList.first?.similarity ?? 0.0
        let titleSim = titleResList.first?.similarity ?? 0.0
        window.swBestSimilarity = max(nameSim * 1.02, titleSim)
        window.lastSearchQuery = query
    }
}

