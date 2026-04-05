import Foundation
import Security

protocol LicenseAPI {
    func activate(_ licenseKey: String, completion: @escaping (Result<ActivateResult, Error>) -> Void)
    func validate(_ licenseKey: String, instanceId: String, completion: @escaping (Result<ValidateResult, Error>) -> Void)
    func deactivate(_ licenseKey: String, instanceId: String, completion: @escaping (Result<Void, Error>) -> Void)
}

struct ActivateResult {
    let instanceId: String
    let variantId: String?
    let customerEmail: String?
}

struct ValidateResult {
    let valid: Bool
    let variantId: String?
}

struct ActiveInstance {
    let id: String
    let machineName: String?
    let lastSeenAt: Date
}

enum LicenseAPIError: LocalizedError {
    case invalidKey
    case activationRejected(String)
    case seatLimitExceeded(instances: [ActiveInstance])
    case deactivationRejected
    case noData
    case invalidResponse(debugInfo: String)
    case apiError(String)
    case keychainWriteFailed(account: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return NSLocalizedString("Invalid license key.", comment: "")
        case .activationRejected(let reason): return reason
        case .seatLimitExceeded: return NSLocalizedString("This license is already activated on the maximum number of machines. Deactivate one to continue.", comment: "")
        case .deactivationRejected: return NSLocalizedString("Deactivation was rejected by the server.", comment: "")
        case .noData: return NSLocalizedString("No response from server.", comment: "")
        case .invalidResponse: return NSLocalizedString("Unexpected response from server.", comment: "")
        case .apiError(let message): return message
        case .keychainWriteFailed: return NSLocalizedString("Couldn't save your license to the macOS Keychain. Please share the details below with the developer.", comment: "")
        }
    }

    var debugInfo: String? {
        switch self {
        case .invalidResponse(let info): return info
        case .keychainWriteFailed(let account, let status):
            return "Keychain write failed: account=\(account), \(SystemKeychain.describe(status))"
        default: return nil
        }
    }
}
