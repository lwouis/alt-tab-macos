//
//  NSColor.swift
//  alt-tab-macos
//
//  Created by Ismatulla Mansurov on 7/25/23.
//  Copyright © 2023 lwouis. All rights reserved.
//

import Foundation

extension NSColor {
    static var fontColor: NSColor {
        if NSAppearance.current.isDarkMode {
            return .white
        } else {
            return .black
        }
    }
}
