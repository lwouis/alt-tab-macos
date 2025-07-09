//
//  BackgroundView.swift
//  alt-tab-macos
//
//  Created by Titouan on 09/07/2025.
//  Copyright © 2025 lwouis. All rights reserved.
//


import Cocoa

class BackgroundView: NSView {
    private var backgroundView: NSView

    override init(frame frameRect: NSRect) {
        if #available(macOS 16.0, *) {
            let glassView = NSGlassEffectView()
//            glassView.tintColor = Appearance.nsGlassEffectTintColor
            backgroundView = glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = Appearance.material
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            backgroundView = effectView
        }

        super.init(frame: frameRect)

        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateMaterial() {
        if #available(macOS 26.0, *) {
//            (backgroundView as! NSGlassEffectView).tintColor = Appearance.nsGlassEffectTintColor
        } else {
            (backgroundView as! NSVisualEffectView).material = Appearance.material
        }
    }

    func updateRoundedCorners(_ cornerRadius: CGFloat) {
        if #available(macOS 26.0, *) {
           (backgroundView as! NSGlassEffectView).cornerRadius = cornerRadius
        } else {
            if cornerRadius == 0 {
                (backgroundView as! NSVisualEffectView).maskImage = nil
            } else {
                let edgeLength = 2.0 * cornerRadius + 1.0
                let mask = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
                    let bezierPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                    NSColor.black.set()
                    bezierPath.fill()
                    return true
                }
                mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
                mask.resizingMode = .stretch
                (backgroundView as! NSVisualEffectView).maskImage = mask
            }
        }
    }
}
