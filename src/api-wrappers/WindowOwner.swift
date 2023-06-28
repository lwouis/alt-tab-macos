//
// Created by Zachary Wander on 6/27/23.
// Copyright (c) 2023 lwouis. All rights reserved.
//

import Foundation

class WindowOwner {
    var window: Window
    var connection: CGSConnectionID

    init(_ window: Window, _ connection: CGSConnectionID) {
        self.window = window
        self.connection = connection
    }

    func setActive(_ active: Bool) {
        CGSSetWindowActive(connection, window.cgWindowId!, active)
    }
}
