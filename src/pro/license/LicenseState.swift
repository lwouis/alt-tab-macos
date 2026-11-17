enum LicenseState: Equatable {
    case unrestricted
    case trialNotStarted
    case trial(daysRemaining: Int)
    case pro
    case proExpired
    case trialExpired

    var isProAvailable: Bool {
        switch self {
        case .unrestricted, .trial, .pro: return true
        case .trialNotStarted, .proExpired, .trialExpired: return false
        }
    }

    var debugProfileLabel: String {
        switch self {
        case .unrestricted: return "Community"
        case .trialNotStarted: return "Setup"
        case .trial: return "Trial"
        case .pro: return "Pro"
        case .proExpired, .trialExpired: return "Free"
        }
    }

    /// Setup has no tier yet. The appcast tag distinguishes expired Pro from expired trials;
    /// `debugProfileLabel` and the analytics view group both as Free.
    var appcastTier: String {
        switch self {
        case .unrestricted: return ""
        case .trialNotStarted: return ""
        case .trial: return "trial"
        case .pro: return "pro"
        case .proExpired: return "proExpired"
        case .trialExpired: return "trialExpired"
        }
    }
}
