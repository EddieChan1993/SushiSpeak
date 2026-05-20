#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Draw the SushiSpeak icon at a given size into an NSImage
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let pad = s * 0.08

    // --- Background: rounded square, warm salmon-red ---
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.22
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: bgRect, cornerWidth: radius, cornerHeight: radius)
    ctx.setFillColor(CGColor(red: 0.94, green: 0.30, blue: 0.25, alpha: 1))
    ctx.addPath(bgPath)
    ctx.fillPath()

    // Subtle inner glow / lighter top
    let gradColors = [
        CGColor(red: 1.0, green: 0.52, blue: 0.38, alpha: 0.55),
        CGColor(red: 1.0, green: 0.52, blue: 0.38, alpha: 0.0)
    ] as CFArray
    let gradLocs: [CGFloat] = [0, 1]
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: gradLocs) {
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: s * 0.5, y: s),
            end:   CGPoint(x: s * 0.5, y: s * 0.4),
            options: [])
        ctx.restoreGState()
    }

    // === SUSHI ROLL (maki, top-down view) ===
    let cx = s * 0.42
    let cy = s * 0.50
    let outerR = s * 0.285
    let noriR  = outerR
    let riceR  = outerR * 0.78
    let fillR  = outerR * 0.52

    // Nori (dark seaweed band)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - noriR, y: cy - noriR, width: noriR*2, height: noriR*2))

    // Rice ring (white)
    ctx.setFillColor(CGColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - riceR, y: cy - riceR, width: riceR*2, height: riceR*2))

    // Salmon filling (center)
    ctx.setFillColor(CGColor(red: 0.98, green: 0.62, blue: 0.42, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - fillR, y: cy - fillR, width: fillR*2, height: fillR*2))

    // Highlight dot on salmon
    let hlR = fillR * 0.28
    ctx.setFillColor(CGColor(red: 1.0, green: 0.82, blue: 0.70, alpha: 0.7))
    ctx.fillEllipse(in: CGRect(x: cx - hlR * 0.4, y: cy + hlR * 0.2, width: hlR*2, height: hlR*2))

    // === SOUND WAVES (right side) ===
    let waveX = cx + outerR + s * 0.045
    let waveY = cy
    let waveColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92)
    ctx.setStrokeColor(waveColor)
    ctx.setLineCap(.round)

    let lineWidth = s * 0.035
    ctx.setLineWidth(lineWidth)

    // Three arcs, getting larger
    let arcs: [(CGFloat, CGFloat)] = [
        (s * 0.065, CGFloat.pi * 0.55),
        (s * 0.115, CGFloat.pi * 0.50),
        (s * 0.165, CGFloat.pi * 0.45)
    ]
    for (r, span) in arcs {
        ctx.addArc(center: CGPoint(x: waveX, y: waveY),
                   radius: r,
                   startAngle: -span / 2,
                   endAngle:    span / 2,
                   clockwise: false)
        ctx.strokePath()
    }

    // Small circle at wave origin (speaker dot)
    let dotR = lineWidth * 0.9
    ctx.setFillColor(waveColor)
    ctx.fillEllipse(in: CGRect(x: waveX - dotR, y: waveY - dotR, width: dotR*2, height: dotR*2))

    image.unlockFocus()
    return image
}

// Save NSImage as PNG file
func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to encode PNG: \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("  wrote \(path)")
    } catch {
        print("Error writing \(path): \(error)")
    }
}

let sizes: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

let iconsetDir = "Assets/AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: "Assets", withIntermediateDirectories: true)
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    savePNG(img, to: "\(iconsetDir)/\(name).png")
}

print("Iconset ready at \(iconsetDir)")
