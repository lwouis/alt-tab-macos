// PROTOTYPE, throwaway: compares Clear glass Tint strengths and selection highlights over a dark backdrop.
// Not part of the app target. Run: swift src/switcher/main-window/prototype-tint-highlight/main.swift
// Close the window (or press Esc) to quit.
import AppKit

let tints: [CGFloat] = [0.2, 0.35, 0.5, 0.65]
let highlights: [(name: String, fill: NSColor, border: NSColor?)] = [
    ("A  no highlight", .clear, nil),
    ("B  current: accent 20% + border", NSColor.controlAccentColor.withAlphaComponent(0.2), .controlAccentColor),
    ("C  accent 50% + border", NSColor.controlAccentColor.withAlphaComponent(0.5), .controlAccentColor),
    ("D  white 15% + border", NSColor.white.withAlphaComponent(0.15), .controlAccentColor),
    ("E  black 45% + border", NSColor.black.withAlphaComponent(0.45), .controlAccentColor),
]
let panelW: CGFloat = 330, rowH: CGFloat = 34, pad: CGFloat = 14, headerH: CGFloat = 28
let panelH = headerH + CGFloat(highlights.count) * (rowH + 6) + pad * 2
let screen = NSScreen.main!.visibleFrame
let totalW = CGFloat(tints.count) * (panelW + 20) + 20
let origin = NSPoint(x: screen.midX - totalW / 2, y: screen.midY - 200)

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

func titleFont() -> NSFont { NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14) }

func title(_ text: String) -> NSTextField {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 2
    shadow.shadowOffset = .zero
    let label = NSTextField(labelWithString: "")
    label.attributedStringValue = NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.white, .font: titleFont(), .shadow: shadow])
    return label
}

func backdrop() -> NSWindow {
    let frame = NSRect(x: origin.x - 40, y: origin.y - 60, width: totalW + 80, height: panelH * 2 + 120)
    let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    let v = NSView(frame: NSRect(origin: .zero, size: frame.size))
    v.wantsLayer = true
    v.layer!.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
    for i in 0..<Int(frame.height / 22) {
        let line = NSView(frame: NSRect(x: 30 + CGFloat(i * 37 % 120), y: CGFloat(i) * 22 + 6, width: CGFloat(200 + i * 53 % 500), height: 9))
        line.wantsLayer = true
        line.layer!.backgroundColor = NSColor(calibratedHue: CGFloat(i % 5) / 5, saturation: 0.35, brightness: 0.45, alpha: 1).cgColor
        line.layer!.cornerRadius = 3
        v.addSubview(line)
    }
    w.contentView = v
    return w
}

func panel(tint: CGFloat) -> NSGlassEffectView {
    let g = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
    g.style = .clear
    let sel = NSSelectorFromString("set_variant:")
    typealias SetVariant = @convention(c) (AnyObject, Selector, Int) -> Void
    if let m = class_getInstanceMethod(object_getClass(g), sel) { unsafeBitCast(method_getImplementation(m), to: SetVariant.self)(g, sel, 3) }
    g.cornerRadius = 23
    let host = NSView(frame: g.bounds)
    host.wantsLayer = true
    host.layer!.backgroundColor = NSColor.black.withAlphaComponent(tint).cgColor
    let header = title("Tint \(tint)")
    header.frame = NSRect(x: pad, y: panelH - pad - headerH + 4, width: panelW - pad * 2, height: 20)
    host.addSubview(header)
    for (i, h) in highlights.enumerated() {
        let y = panelH - pad - headerH - CGFloat(i + 1) * (rowH + 6)
        let row = NSView(frame: NSRect(x: pad, y: y, width: panelW - pad * 2, height: rowH))
        row.wantsLayer = true
        row.layer!.cornerRadius = 8
        row.layer!.backgroundColor = h.fill.cgColor
        if let border = h.border { row.layer!.borderColor = border.cgColor; row.layer!.borderWidth = 2 }
        let label = title("\(h.name) · Safari – Inbox")
        label.frame = NSRect(x: 10, y: (rowH - 20) / 2, width: row.frame.width - 20, height: 20)
        row.addSubview(label)
        host.addSubview(row)
    }
    g.contentView = host
    return g
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let back = backdrop()
back.orderFront(nil)
let glass = NSWindow(contentRect: NSRect(x: origin.x, y: origin.y, width: totalW, height: panelH + 40), styleMask: [.titled, .closable], backing: .buffered, defer: false)
glass.title = "PROTOTYPE · Tint × highlight over a dark backdrop — Esc or close to quit"
glass.isOpaque = false
glass.backgroundColor = .clear
glass.titlebarAppearsTransparent = true
glass.appearance = NSAppearance(named: .vibrantDark)
glass.delegate = delegate
let root = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: panelH + 40))
for (i, t) in tints.enumerated() {
    let p = panel(tint: t)
    p.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * (panelW + 20), y: 20))
    root.addSubview(p)
}
glass.contentView = root
glass.level = .floating
glass.makeKeyAndOrderFront(nil)
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in if e.keyCode == 53 { NSApp.terminate(nil) }; return e }
print("Tints: \(tints)  Highlights: \(highlights.map(\.name))")
app.activate(ignoringOtherApps: true)
app.run()
