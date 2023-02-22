import M5MultitouchSupport

//TODO: patch M5MultitouchSupport pod to make it not to crash after sleep. See https://github.com/mhuusko5/M5MultitouchSupport/issues/1
//TODO: App Expose activates if swipe down with 3-fingers right after AltTab activation. There is no issue if wait for some time.
//TODO: enable/disable trackpad usage in settings
class TrackpadEvents {
    //TODO: Should we add a sensetivity setting instead of these magic numbers?
    private static let accVelXThreshold: Float = 10
    private static let accVelYThreshold: Float = 15
    
    private static var listener: M5MultitouchListener?

    static func addSwipeListener() {
        var accVelX: Float = 0
        var accVelY: Float = 0
        // We need to track an UI activation via gesture to not to hide UI on trackpad events for other activations.
        var activated: Bool = false

        listener = M5MultitouchManager.shared().addListener {event in
            if event == nil {
                return
            }

            let touches = event!.touches as! [M5MultitouchTouch]

            // We don't care about non-3-fingers swipes.
            if touches.count != 3 {
                // Except when we already started a gesture, so we need to end it.
                if activated {
                    if App.app.appIsBeingUsed {
                        DispatchQueue.main.async {
                            App.app.focusTarget()
                            App.app.hideUi()
                        }
                    }
                    accVelX = 0
                    accVelY = 0
                    activated = false
                }
                return
            }

            let velocity = swipeVelocity(touches: touches)
            // We don't care about gestures other than horizontal or vertical swipes.
            if velocity == nil {
                return
            }

            accVelX += velocity!.x
            accVelY += velocity!.y
            // Not enough swiping.
            if abs(accVelX) < accVelXThreshold && abs(accVelY) < accVelYThreshold {
                return
            }

            let isHorizontal = abs(velocity!.x) > abs(velocity!.y)
            if App.app.appIsBeingUsed {
                let direction: Direction = isHorizontal
                    ? accVelX < 0 ? .left : .right
                    : accVelY < 0 ? .down : .up
                DispatchQueue.main.async { App.app.cycleSelection(direction) }
            } else {
                if isHorizontal {
                    DispatchQueue.main.async { App.app.showUi() }
                    activated = true
                }
            }
            accVelX = 0
            accVelY = 0
        }
    }

    private static func swipeVelocity(touches: [M5MultitouchTouch]) -> (x: Float, y: Float)? {
        var allRight = true
        var allLeft = true
        var allUp = true
        var allDown = true
        var sumVelX = Float(0)
        var sumVelY = Float(0)
        for touch in touches {
            allRight = allRight && touch.velX >= 0
            allLeft = allLeft && touch.velX <= 0
            allUp = allUp && touch.velY >= 0
            allDown = allDown && touch.velY <= 0
            sumVelX += touch.velX
            sumVelY += touch.velY
        }
        // All fingers should move in the same direction.
        if !allRight && !allLeft && !allUp && !allDown {
            return nil
        }

        let velX = sumVelX / Float(touches.count)
        let velY = sumVelY / Float(touches.count)
        return (velX, velY)
    }

    static func removeSwipeListener() {
        if listener != nil {
            M5MultitouchManager.shared().remove(listener)
        }
    }
}
