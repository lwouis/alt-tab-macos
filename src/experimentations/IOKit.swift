import Foundation
import IOKit.hid
import Carbon.HIToolbox
import CoreGraphics

class IOKitPrototype {
    static let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    static func initialize() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, keyboardEventHandler, nil)
        IOHIDManagerScheduleWithRunLoop(manager, BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop!, CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

func keyCodeToString(keyCode: UInt32) -> String? {
    guard let keyboardLayoutPtr = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
        print("Could not retrieve keyboard layout data")
        return nil
    }
    guard let layoutDataPtr = TISGetInputSourceProperty(keyboardLayoutPtr, kTISPropertyUnicodeKeyLayoutData) else {
        print("Keyboard layout data is nil")
        return nil
    }
    let layoutBytes = CFDataGetBytePtr(unsafeBitCast(layoutDataPtr, to: CFData.self))
    let layoutPtr = unsafeBitCast(layoutBytes, to: UnsafePointer<UCKeyboardLayout>.self)
    var chars: [UniChar] = Array(repeating: 0, count: 4)
    var actualLength: Int = 0
    let modifierFlags = UInt32(0) // You can populate this based on event flags if available
    var deadKeyState: UInt32 = 0
    let osStatus = UCKeyTranslate(
        layoutPtr,
        UInt16(keyCode), // Adjust usage to match standard key mapping
        UInt16(kUCKeyActionDown), // Pressed key
        modifierFlags,
        UInt32(LMGetKbdType()), // Keyboard Type
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &actualLength,
        &chars
    )
    if osStatus == noErr, actualLength > 0 {
        return String(utf16CodeUnits: chars, count: actualLength)
    }
    return nil
}

func keyCodeToStringUsingCG(keyCode: UInt32) -> String? {
    // Create a CGEventSource to simulate the event
//    let eventSource = CGEventSource(stateID: .hidSystemState)
    // Create a keydown event for the specified keycode
    let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
    // Create a buffer to store the Unicode string result
    var unicodeString = [UniChar](repeating: 0, count: 4)
    var actualLength: Int = 0
    // Get the Unicode string corresponding to the key press
    keyDownEvent?.keyboardGetUnicodeString(maxStringLength: unicodeString.count, actualStringLength: &actualLength, unicodeString: &unicodeString)
    // Check if the call was successful and return the corresponding string
    if actualLength > 0 {
        return String(utf16CodeUnits: unicodeString, count: actualLength)
    }
    // If something went wrong, return nil
    print("Failed to get Unicode string for keycode \(keyCode)")
    return nil
}

func keyboardEventHandler(_: UnsafeMutableRawPointer?, _: IOReturn, _: UnsafeMutableRawPointer?, event: IOHIDValue) {
    let element = IOHIDValueGetElement(event)
    if IOHIDElementGetUsagePage(element) != kHIDPage_KeyboardOrKeypad {
        return
    }
    let scancode = IOHIDElementGetUsage(element)
    if scancode < 4 || scancode > 231 {
        return
    }
    let pressed = IOHIDValueGetIntegerValue(event) == 1
    // TIS calls have to happen on the main thread
    // Apple docs: TextInputSources API is not thread safe. If you are a UI application, you must call TextInputSources API on the main thread
    DispatchQueue.main.sync {
        let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
//        print(inputSource)
        let inputSourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)!
        let sourceId = unsafeBitCast(inputSourceID, to: CFString?.self)
//        print("Input Source ID: \(sourceId)")
//        print(scancode, keyCodeToString(keyCode: scancode))
//        print(scancode, keyCodeToStringUsingCG(keyCode: scancode))
//        let keyCode = Int(scancode - 4) // Subtract 4 to align with key codes in `UCKeyTranslate`
//        if let keyString = keyCodeToString(keyCode: keyCode) {
//            let state = pressed ? "Pressed" : "Released"
//            print("Key '\(keyString)' \(state)")
//        } else {
//            let state = pressed ? "Pressed" : "Released"
//            print("Key Code \(keyCode) \(state)")
//        }
    }
}
