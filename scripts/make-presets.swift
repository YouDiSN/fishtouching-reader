import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(1) }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let size = 1024

func color(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func drawFish() {
    let fish = NSBezierPath()
    fish.move(to: NSPoint(x: 286, y: 494))
    fish.curve(to: NSPoint(x: 778, y: 504), controlPoint1: NSPoint(x: 424, y: 726), controlPoint2: NSPoint(x: 683, y: 687))
    fish.curve(to: NSPoint(x: 286, y: 494), controlPoint1: NSPoint(x: 681, y: 326), controlPoint2: NSPoint(x: 430, y: 286))
    fish.close()
    color(0xA5E6D2).setFill(); fish.fill()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 344, y: 500))
    tail.line(to: NSPoint(x: 214, y: 626))
    tail.line(to: NSPoint(x: 218, y: 385))
    tail.close()
    color(0x69C9BD).setFill(); tail.fill()

    let fin = NSBezierPath()
    fin.move(to: NSPoint(x: 495, y: 607))
    fin.curve(to: NSPoint(x: 598, y: 696), controlPoint1: NSPoint(x: 502, y: 704), controlPoint2: NSPoint(x: 564, y: 711))
    fin.line(to: NSPoint(x: 638, y: 619))
    fin.close()
    color(0x69C9BD).setFill(); fin.fill()

    color(0x173F52).setFill()
    NSBezierPath(ovalIn: NSRect(x: 694, y: 527, width: 24, height: 24)).fill()
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: 738, y: 472))
    smile.curve(to: NSPoint(x: 699, y: 463), controlPoint1: NSPoint(x: 725, y: 453), controlPoint2: NSPoint(x: 712, y: 453))
    smile.lineWidth = 9; smile.lineCapStyle = .round
    color(0x267E83).setStroke(); smile.stroke()

    let handStyle = NSImage.SymbolConfiguration(pointSize: 380, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color(0xFFD3A6)]))
    if let hand = NSImage(systemSymbolName: "hand.point.down.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(handStyle) {
        hand.draw(in: NSRect(x: 443, y: 591, width: 355, height: 355),
                  from: .zero, operation: .sourceOver, fraction: 1)
    }
}

let presets: [(id: String, symbol: String, start: UInt32, end: UInt32)] = [
    ("fish", "", 0x15546A, 0x132C45),
    ("night", "moon.stars.fill", 0x53538F, 0x202640),
    ("leaf", "leaf.fill", 0x5B9D73, 0x193C31),
    ("coffee", "cup.and.saucer.fill", 0xA86F57, 0x482C32),
    ("star", "star.fill", 0xBC8643, 0x4E3050),
    ("pencil", "pencil", 0x647FA5, 0x25384F),
    ("music", "music.note", 0x8B68A7, 0x352D55),
    ("sunrise", "sun.horizon.fill", 0xD7896D, 0x693B60),
    ("cloud", "cloud.fill", 0x5F9AA9, 0x273F5F)
]

for preset in presets {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    let inset = NSAffineTransform()
    inset.translateX(by: 512, yBy: 512)
    inset.scale(by: 0.88)
    inset.translateX(by: -512, yBy: -512)
    inset.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936),
                                  xRadius: 205, yRadius: 205)
    NSGradient(starting: color(preset.start), ending: color(preset.end))!.draw(in: background, angle: -55)
    if preset.id == "fish" {
        drawFish()
    } else {
        let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color(0xF7F2DE)]))
        if let image = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.draw(in: NSRect(x: 211, y: 211, width: 602, height: 602),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: directory.appendingPathComponent("\(preset.id).png"), options: .atomic)
}
