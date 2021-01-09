//
//  String+BASE64.swift
//  Swifter
//
//  Copyright © 2016 Damian Kołakowski. All rights reserved.
//

import Foundation

extension String {

    public static func toBase64(_ data: [UInt8]) -> String {
        return Data(data).base64EncodedString()
    }
}
