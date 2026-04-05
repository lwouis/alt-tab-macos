import Foundation

// Values are substituted into Info.plist from xcconfig at build time.
// Defaults: config/base.xcconfig. Per-dev or CI overrides: config/local.xcconfig.
enum Secrets {
    static let appCenterSecret = Bundle.main.object(forInfoDictionaryKey: "AppCenterSecret") as! String
}
