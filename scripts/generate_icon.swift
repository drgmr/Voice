#!/usr/bin/env swift
import AppKit
import Foundation

// Renders the Voice app icon in the same gradient + mic aesthetic as
// the in-app AppLogo in WelcomeView. Writes one PNG per required size
// into Voice/Assets.xcassets/AppIcon.appiconset and updates
// Contents.json so the asset catalog picks them up.
//
// Run:  swift scripts/generate_icon.swift
// Then rebuild the app in Xcode to see the new icon.

struct IconSize {
    let logicalPt: Int
    let scale: Int
    var pixels: Int { logicalPt * scale }
    var filename: String { "icon_\(logicalPt)x\(logicalPt)@\(scale)x.png" }
}

let sizes: [IconSize] = [
    IconSize(logicalPt: 16,  scale: 1),
    IconSize(logicalPt: 16,  scale: 2),
    IconSize(logicalPt: 32,  scale: 1),
    IconSize(logicalPt: 32,  scale: 2),
    IconSize(logicalPt: 128, scale: 1),
    IconSize(logicalPt: 128, scale: 2),
    IconSize(logicalPt: 256, scale: 1),
    IconSize(logicalPt: 256, scale: 2),
    IconSize(logicalPt: 512, scale: 1),
    IconSize(logicalPt: 512, scale: 2),
]

func render(sizePx: Int) -> Data {
    let px = CGFloat(sizePx)
    let image = NSImage(size: NSSize(width: px, height: px))
    image.lockFocus()

    // macOS app icons get composited with a small shadow; the artwork
    // itself sits on an ~82% inset squircle so the final icon matches
    // the rest of the dock.
    let inset = px * 0.09
    let artRect = NSRect(x: inset, y: inset, width: px - 2 * inset, height: px - 2 * inset)
    let cornerRadius = artRect.width * 0.225 // standard macOS squircle ratio

    let path = NSBezierPath(roundedRect: artRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.37, green: 0.36, blue: 0.90, alpha: 1.0),
        NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0),
    ])!
    gradient.draw(
        from: NSPoint(x: artRect.minX, y: artRect.maxY),
        to: NSPoint(x: artRect.maxX, y: artRect.minY),
        options: []
    )

    // Mic glyph — use SF Symbols, white, centered.
    let micSize = artRect.width * 0.55
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: micSize, weight: .semibold)
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = NSImage(size: mic.size, flipped: false) { rect in
            NSColor.white.set()
            rect.fill()
            mic.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
        let glyphRect = NSRect(
            x: artRect.midX - tinted.size.width / 2,
            y: artRect.midY - tinted.size.height / 2,
            width: tinted.size.width,
            height: tinted.size.height
        )
        tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed at \(sizePx)px")
    }
    return png
}

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconsetURL = projectRoot
    .appending(component: "Voice")
    .appending(component: "Assets.xcassets")
    .appending(component: "AppIcon.appiconset")

for size in sizes {
    let data = render(sizePx: size.pixels)
    let url = iconsetURL.appending(component: size.filename)
    try data.write(to: url)
    print("wrote \(size.filename) (\(size.pixels)×\(size.pixels))")
}

// Rewrite Contents.json so every entry references its filename.
var images: [[String: String]] = []
for size in sizes {
    images.append([
        "idiom": "mac",
        "scale": "\(size.scale)x",
        "size": "\(size.logicalPt)x\(size.logicalPt)",
        "filename": size.filename,
    ])
}
let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconsetURL.appending(component: "Contents.json"))
print("updated Contents.json")
