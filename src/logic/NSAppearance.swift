//
//  NSAppearance.swift
//  alt-tab-macos
//
//  Created by Ismatulla Mansurov on 7/25/23.
//  Copyright © 2023 lwouis. All rights reserved.
//

import Foundation

extension NSAppearance {
    var isDarkMode: Bool {
        if #available(macOS 10.14, *) {
            let isDarkMode = bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDarkMode
        } else {
            return false
        }
    }
}
