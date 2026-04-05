enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case pro
    case proExpired
    case trialExpired

    var isProAvailable: Bool {
        switch self {
        case .trial, .pro: return true
        case .proExpired, .trialExpired: return false
        }
    }

    var debugProfileLabel: String {
        switch self {
        case .trial: return "Trial"
        case .pro: return "Pro"
        case .proExpired, .trialExpired: return "Free"
        }
    }
}
