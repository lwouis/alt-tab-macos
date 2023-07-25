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
            return NSColor(red: 0.725, green: 0.733, blue: 0.788, alpha: 1.0) // Same font color for dark mode used in Ventura tab switcher
        } else {
            return NSColor(red: 0.510, green: 0.506, blue: 0.518, alpha: 1.0) // same but for the light mode
        }
    }
    
    static var highlightBackgroundColor: NSColor {
        if NSAppearance.current.isDarkMode {
            return NSColor(red: 0.090, green: 0.090, blue: 0.118, alpha: 1.0)
        } else {
            return NSColor(red: 0.714, green: 0.694, blue: 0.729, alpha: 1.0)
        }
    }
}
