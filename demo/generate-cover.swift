import AppKit
import CoreGraphics
import Foundation

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let source = directory.appendingPathComponent("fixtures/正式.txt")
let destination = directory.appendingPathComponent("fixtures/工作汇报.pdf")
let lines = try String(contentsOf: source, encoding: .utf8).components(separatedBy: .newlines)
let buffer = NSMutableData()
guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else { fatalError("PDF consumer") }
var page = CGRect(x: 0, y: 0, width: 595, height: 842)
guard let pdf = CGContext(consumer: consumer, mediaBox: &page, nil) else { fatalError("PDF context") }
pdf.beginPDFPage(nil)
pdf.setFillColor(NSColor.white.cgColor)
pdf.fill(page)
pdf.setFillColor(NSColor(calibratedRed: 0.14, green: 0.31, blue: 0.27, alpha: 1).cgColor)
pdf.fill(CGRect(x: 0, y: 808, width: 595, height: 34))

let graphics = NSGraphicsContext(cgContext: pdf, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
var y: CGFloat = 745
for (index, line) in lines.enumerated() {
    if line.isEmpty { y -= 14; continue }
    let isTitle = index == 0
    let isSection = ["本周进展", "下周计划", "需要关注"].contains(line)
    let size: CGFloat = isTitle ? 25 : (isSection ? 15 : 12)
    let font = NSFont(name: isTitle || isSection ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: size)
        ?? NSFont.systemFont(ofSize: size)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: isTitle ? NSColor(calibratedRed: 0.13, green: 0.27, blue: 0.24, alpha: 1) : NSColor(calibratedWhite: 0.24, alpha: 1)
    ]
    let text = NSAttributedString(string: line, attributes: attributes)
    let height = max(size * 1.5, text.boundingRect(with: NSSize(width: 480, height: 100), options: [.usesLineFragmentOrigin]).height)
    text.draw(in: NSRect(x: 58, y: y - height, width: 480, height: height + 2))
    y -= height + (isTitle ? 16 : isSection ? 10 : 7)
}
NSGraphicsContext.restoreGraphicsState()
pdf.endPDFPage()
pdf.closePDF()
try (buffer as Data).write(to: destination, options: .atomic)
print(destination.path)
