import Foundation

enum Endpoints {
    static let domain = Bundle.main.object(forInfoDictionaryKey: "Domain") as! String
    static let apiDomain = Bundle.main.object(forInfoDictionaryKey: "ApiDomain") as! String
    static let website = "https://\(domain)"
    static let appcastUrl = "\(website)/appcast.xml"
    static let supportUrl = "\(website)/support"
    static let accountUrl = "\(website)/my-account"
    static let licenseApiBaseUrl = "https://\(apiDomain)/v1/license"
    static let feedbackUrl = "https://\(apiDomain)/v1/feedback"

    /// `?via=` is the trial day, a dash, then the origin's code (day 35 from the Day 35 window → `35-a6`), so the day
    /// reads as-is in raw logs. Without a trial day it's the origin code alone. The website splits the two apart.
    static func checkoutUrl(from origin: CheckoutOrigin, trialDay: Int?, website: String = website) -> URL {
        var components = URLComponents(string: "\(website)/pricing")!
        let day = trialDay.map { "\($0)-" } ?? ""
        components.queryItems = [URLQueryItem(name: "via", value: day + origin.rawValue)]
        return components.url!
    }
}

/// Which "Get Pro" entry point opened the pricing page. The website copies `?via=` into the Paddle checkout, so a
/// sale can be traced back to the prompt that led to it. Codes are deliberately opaque: the URL the user sees says
/// nothing about the prompt schedule. The website accepts only these values, so keep its list in sync, and never reuse
/// a retired code. Retired: "a1", the Day 12 heads-up; "a3", the timed Day 15 window; "a5", the Day 21 reminder.
enum CheckoutOrigin: String, CaseIterable {
    case fullUpgrade = "a2"
    case hardGate = "a4"
    case day35Final = "a6"
    case settingsUpgradeTab = "a7"
    case menubar = "a8"
}
