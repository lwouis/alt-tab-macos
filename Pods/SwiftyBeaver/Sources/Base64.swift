//
//  Base64.swift
//  SwiftyBeaver (macOS)
//
//  Copyright © 2017 Sebastian Kreutzberger. All rights reserved.
//
#if os(Linux)
import Foundation

struct InvalidBase64: Error {}

struct Base64 {
    static func decode(_ string: String) throws -> [UInt8] {
        return try decode([UInt8](string.utf8))
    }

    /// Decodes a Base64 encoded String into Data
    ///
    /// - throws: If the string isn't base64 encoded
    static func decode(_ string: [UInt8]) throws -> [UInt8] {
        let lookupTable: [UInt8] = [
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 62, 64, 62, 64, 63,
            52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 64, 64, 64, 64, 64, 64,
            64, 00, 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14,
            15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 64, 64, 64, 64, 63,
            64, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
            41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64
            ]

        let remainder = string.count % 4
        let length = (string.count - remainder) / 4

        var decoded = [UInt8]()
        decoded.reserveCapacity(length)

        var index = 0
        var i0: UInt8 = 0
        var i1: UInt8 = 0
        var i2: UInt8 = 0
        var i3: UInt8 = 0

        while index &+ 4 < string.count {
            i0 = lookupTable[numericCast(string[index])]
            i1 = lookupTable[numericCast(string[index &+ 1])]
            i2 = lookupTable[numericCast(string[index &+ 2])]
            i3 = lookupTable[numericCast(string[index &+ 3])]

            if i0 > 63 || i1 > 63 || i2 > 63 || i3 > 63 {
                throw InvalidBase64()
            }

            decoded.append(i0 << 2 | i1 >> 4)
            decoded.append(i1 << 4 | i2 >> 2)
            decoded.append(i2 << 6 | i3)
            index += 4
        }

        if string.count &- index > 1 {
            i0 = lookupTable[numericCast(string[index])]
            i1 = lookupTable[numericCast(string[index &+ 1])]

            if i1 > 63 {
                guard string[index] == 61 else {
                    throw InvalidBase64()
                }

                return decoded
            }

            if i2 > 63 {
                guard string[index &+ 2] == 61 else {
                    throw InvalidBase64()
                }

                return decoded
            }

            decoded.append(i0 << 2 | i1 >> 4)

            if string.count &- index > 2 {
                i2 = lookupTable[numericCast(string[index &+ 2])]

                if i2 > 63 {
                    guard string[index &+ 2] == 61 else {
                        throw InvalidBase64()
                    }

                    return decoded
                }

                decoded.append(i1 << 4 | i2 >> 2)

                if string.count &- index > 3 {
                    i3 = lookupTable[numericCast(string[index &+ 3])]

                    if i3 > 63 {
                        guard string[index &+ 3] == 61 else {
                            throw InvalidBase64()
                        }

                        return decoded
                    }

                    decoded.append(i2 << 6 | i3)
                }
            }
        }

        return decoded
    }

    static func encode(_ data: [UInt8]) -> String {
        let base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var encoded: String = ""

        func appendCharacterFromBase(_ character: Int) {
            encoded.append(base64[base64.index(base64.startIndex, offsetBy: character)])
        }

        func byte(_ index: Int) -> Int {
            return Int(data[index])
        }

        let decodedBytes = data.map { Int($0) }

        var i = 0

        while i < decodedBytes.count - 2 {
            appendCharacterFromBase((byte(i) >> 2) & 0x3F)
            appendCharacterFromBase(((byte(i) & 0x3) << 4) | ((byte(i + 1) & 0xF0) >> 4))
            appendCharacterFromBase(((byte(i + 1) & 0xF) << 2) | ((byte(i + 2) & 0xC0) >> 6))
            appendCharacterFromBase(byte(i + 2) & 0x3F)
            i += 3
        }

        if i < decodedBytes.count {
            appendCharacterFromBase((byte(i) >> 2) & 0x3F)

            if i == decodedBytes.count - 1 {
                appendCharacterFromBase(((byte(i) & 0x3) << 4))
                encoded.append("=")
            } else {
                appendCharacterFromBase(((byte(i) & 0x3) << 4) | ((byte(i + 1) & 0xF0) >> 4))
                appendCharacterFromBase(((byte(i + 1) & 0xF) << 2))
            }

            encoded.append("=")
        }

        return encoded
    }
}

#endif
