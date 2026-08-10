import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-dmg-background.swift OUTPUT.png\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 420)
let image = NSImage(size: size)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
NSGradient(
    starting: NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.085, alpha: 1),
    ending: NSColor(calibratedRed: 0.015, green: 0.018, blue: 0.023, alpha: 1)
)?.draw(in: bounds, angle: -90)

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: titleStyle,
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
    .paragraphStyle: titleStyle,
]

NSString(string: "Install File Island").draw(
    in: NSRect(x: 0, y: 355, width: size.width, height: 28),
    withAttributes: titleAttributes
)
NSString(string: "Drag File Island to Applications  ·  将 File Island 拖入应用程序").draw(
    in: NSRect(x: 0, y: 326, width: size.width, height: 20),
    withAttributes: subtitleAttributes
)

let arrowPath = NSBezierPath()
arrowPath.lineWidth = 5
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.move(to: NSPoint(x: 260, y: 202))
arrowPath.line(to: NSPoint(x: 400, y: 202))
arrowPath.move(to: NSPoint(x: 380, y: 220))
arrowPath.line(to: NSPoint(x: 401, y: 202))
arrowPath.line(to: NSPoint(x: 380, y: 184))
NSColor(calibratedRed: 1, green: 0.69, blue: 0.22, alpha: 0.9).setStroke()
arrowPath.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("error: could not render DMG background\n".utf8))
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
