import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.18, alpha: 1.0).setFill()
    let background = NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)
    background.fill()

    NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.62, alpha: 1.0).setFill()
    let dotRect = NSRect(
        x: CGFloat(size) * 0.18,
        y: CGFloat(size) * 0.68,
        width: CGFloat(size) * 0.18,
        height: CGFloat(size) * 0.18
    )
    NSBezierPath(ovalIn: dotRect).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let text = "IP" as NSString
    let fontSize = CGFloat(size) * 0.34
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let textRect = NSRect(
        x: 0,
        y: CGFloat(size) * 0.22,
        width: CGFloat(size),
        height: CGFloat(size) * 0.42
    )
    text.draw(in: textRect, withAttributes: attributes)

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PNG data for size \(size)"])
    }

    let filename = "icon_\(size)x\(size).png"
    try png.write(to: outputDirectory.appendingPathComponent(filename))
}
