// Tegner app-ikonet og lager mac/AppIcon.icns.
// Bruk:  swift mac/lag-ikon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = root.appendingPathComponent("AppIcon.iconset")
let icns = root.appendingPathComponent("AppIcon.icns")

/// Tegner ikonet på et 1024×1024-lerret (skaleres til hver størrelse).
func drawIcon(in ctx: CGContext) {
    // macOS-ikonrutenettet: innhold på 824×824 med ca. 22 % hjørneradius.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [NSColor(srgbRed: 0.33, green: 0.62, blue: 1.00, alpha: 1).cgColor,
                                       NSColor(srgbRed: 0.24, green: 0.25, blue: 0.86, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // Hvite søkerhjørner.
    let frame = tile.insetBy(dx: 150, dy: 150)
    let arm: CGFloat = 130
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                             (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0),
                             (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                             (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0)] {
        ctx.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    }
    ctx.strokePath()

    // Rød pil fra nede til venstre mot midten, med hvit kant.
    let from = CGPoint(x: 375, y: 375), to = CGPoint(x: 650, y: 650)
    let angle = atan2(to.y - from.y, to.x - from.x)
    let head: CGFloat = 200, spread: CGFloat = .pi / 6.5
    let left = CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread))
    let right = CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread))
    let shaftEnd = CGPoint(x: to.x - head * 0.7 * cos(angle), y: to.y - head * 0.7 * sin(angle))
    let arrow = CGMutablePath()
    arrow.move(to: from)
    arrow.addLine(to: shaftEnd)
    let tip = CGMutablePath()
    tip.move(to: to)
    tip.addLine(to: left)
    tip.addLine(to: right)
    tip.closeSubpath()

    for (color, extra) in [(NSColor.white, CGFloat(36)), (NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1), 0)] {
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(64 + extra)
        ctx.addPath(arrow)
        ctx.strokePath()
        ctx.setLineWidth(18 + extra)
        ctx.addPath(tip)
        ctx.drawPath(using: .fillStroke)
    }
}

func png(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! p.run()
p.waitUntilExit()
try? fm.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "laget: \(icns.path)" : "iconutil feilet")
