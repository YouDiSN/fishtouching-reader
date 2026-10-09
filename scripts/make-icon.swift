import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(1) }
let size = 1024
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
NSGradient(starting: NSColor(red: 0.14, green: 0.33, blue: 0.27, alpha: 1),
           ending: NSColor(red: 0.055, green: 0.12, blue: 0.11, alpha: 1))!
    .draw(in: background, angle: -55)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
shadow.shadowBlurRadius = 32
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()

let left = NSBezierPath()
left.move(to: NSPoint(x: 512, y: 248))
left.curve(to: NSPoint(x: 190, y: 290), controlPoint1: NSPoint(x: 420, y: 300), controlPoint2: NSPoint(x: 275, y: 315))
left.line(to: NSPoint(x: 190, y: 716))
left.curve(to: NSPoint(x: 512, y: 675), controlPoint1: NSPoint(x: 282, y: 695), controlPoint2: NSPoint(x: 418, y: 703))
left.close()
NSColor(red: 0.95, green: 0.93, blue: 0.83, alpha: 1).setFill()
left.fill()

let right = NSBezierPath()
right.move(to: NSPoint(x: 512, y: 248))
right.curve(to: NSPoint(x: 834, y: 290), controlPoint1: NSPoint(x: 604, y: 300), controlPoint2: NSPoint(x: 749, y: 315))
right.line(to: NSPoint(x: 834, y: 716))
right.curve(to: NSPoint(x: 512, y: 675), controlPoint1: NSPoint(x: 742, y: 695), controlPoint2: NSPoint(x: 606, y: 703))
right.close()
NSColor(red: 1, green: 0.98, blue: 0.88, alpha: 1).setFill()
right.fill()
NSShadow().set()

let spine = NSBezierPath()
spine.move(to: NSPoint(x: 512, y: 248))
spine.line(to: NSPoint(x: 512, y: 675))
spine.lineWidth = 12
NSColor(red: 0.19, green: 0.41, blue: 0.34, alpha: 1).setStroke()
spine.stroke()

for y in [575.0, 510.0, 445.0] {
    let leftLine = NSBezierPath()
    leftLine.move(to: NSPoint(x: 250, y: y + 10))
    leftLine.curve(to: NSPoint(x: 462, y: y), controlPoint1: NSPoint(x: 320, y: y + 25), controlPoint2: NSPoint(x: 400, y: y + 18))
    leftLine.lineWidth = 13
    leftLine.lineCapStyle = .round
    NSColor(red: 0.66, green: 0.71, blue: 0.62, alpha: 0.8).setStroke()
    leftLine.stroke()

    let rightLine = NSBezierPath()
    rightLine.move(to: NSPoint(x: 562, y: y))
    rightLine.curve(to: NSPoint(x: 774, y: y + 10), controlPoint1: NSPoint(x: 624, y: y + 18), controlPoint2: NSPoint(x: 704, y: y + 25))
    rightLine.lineWidth = 13
    rightLine.lineCapStyle = .round
    rightLine.stroke()
}

let ribbon = NSBezierPath()
ribbon.move(to: NSPoint(x: 677, y: 682))
ribbon.line(to: NSPoint(x: 677, y: 400))
ribbon.line(to: NSPoint(x: 712, y: 432))
ribbon.line(to: NSPoint(x: 747, y: 400))
ribbon.line(to: NSPoint(x: 747, y: 701))
ribbon.close()
NSColor(red: 0.82, green: 0.43, blue: 0.27, alpha: 1).setFill()
ribbon.fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
