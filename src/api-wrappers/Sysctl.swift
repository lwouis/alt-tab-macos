import Foundation

public struct Sysctl {
    static func run(_ name: String) -> String {
        return run(name, { $0.baseAddress.flatMap { String(validatingUTF8: $0) } }) ?? ""
    }

    static func run<T>(_ name: String, _ type: T.Type) -> T? {
        return run(name, { $0.baseAddress?.withMemoryRebound(to: T.self, capacity: 1) { $0.pointee } })
    }

    static func run(_ keys: [Int32]) -> String? {
        return data(keys)?.withUnsafeBufferPointer() { dataPointer -> String? in
            dataPointer.baseAddress.flatMap { String(validatingUTF8: $0) }
        }
    }

    private static func run<R>(_ name: String, _ fn: (UnsafeBufferPointer<Int8>) -> R?) -> R? {
        return keys(name).flatMap { keys in data(keys)?.withUnsafeBufferPointer() { fn($0) } }
    }

    private static func data(_ keys: [Int32]) -> [Int8]? {
        return keys.withUnsafeBufferPointer() { keysPointer in
            var requiredSize = 0
            let preFlightResult = Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: keysPointer.baseAddress), UInt32(keys.count), nil, &requiredSize, nil, 0)
            if preFlightResult != 0 {
                return nil
            }
            let data = Array<Int8>(repeating: 0, count: requiredSize)
            let result = data.withUnsafeBufferPointer() { dataBuffer -> Int32 in
                return Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: keysPointer.baseAddress), UInt32(keys.count), UnsafeMutableRawPointer(mutating: dataBuffer.baseAddress), &requiredSize, nil, 0)
            }
            if result != 0 {
                return nil
            }
            return data
        }
    }

    private static func keys(_ name: String) -> [Int32]? {
        var keysBufferSize = Int(CTL_MAXNAME)
        var keysBuffer = Array<Int32>(repeating: 0, count: keysBufferSize)
        _ = keysBuffer.withUnsafeMutableBufferPointer { (lbp: inout UnsafeMutableBufferPointer<Int32>) in
            name.withCString { (nbp: UnsafePointer<Int8>) in
                sysctlnametomib(nbp, lbp.baseAddress, &keysBufferSize)
            }
        }
        if keysBuffer.count > keysBufferSize {
            keysBuffer.removeSubrange(keysBufferSize..<keysBuffer.count)
        }
        return keysBuffer
    }
}
