import Foundation

/// Writes a `license` cookie on the alt-tab.app domain so Sparkle's appcast request can be tailored per tier.
/// Called from App.swift's `onStateChanged` hook after every LicenseManager state transition.
func syncLicenseCookie(state: LicenseState) {
    guard let host = URL(string: Endpoints.website)?.host else { return }
    let value: String
    switch state {
    case .pro: value = "pro"
    case .proExpired: value = "proExpired"
    default: value = ""
    }
    let cookie = HTTPCookie(properties: [
        .name: "license",
        .value: value,
        .domain: "." + host,
        .path: "/",
        .expires: Date.distantFuture,
        .secure: true,
    ])
    if let cookie {
        DispatchQueue.global(qos: .default).async {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}
