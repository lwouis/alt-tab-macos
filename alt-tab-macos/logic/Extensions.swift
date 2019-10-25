import Foundation
import Cocoa

// add CGFloat constructor from String
extension CGFloat {
    init?(_ string: String) {
        guard let number = NumberFormatter().number(from: string) else {
            return nil
        }
        self.init(number.floatValue)
    }
}

// add throw-on-nil method on Optional
extension Optional {
    func orThrow() throws -> Wrapped {
        switch self {
        case .some(let value):
            return value
        case .none:
            Thread.callStackSymbols.forEach {
                print($0)
            }
            throw "Optional contained nil"
        }
    }
}

// allow String to be treated as Error (e.g. throw "explanation")
extension String: Error {
}

// add String constructor from CGFloat that round up at 1 decimal
extension String {
    init?(_ cgFloat: CGFloat) {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        guard let string = formatter.string(from: cgFloat as NSNumber) else {
            return nil
        }
        self.init(string)
    }
}
