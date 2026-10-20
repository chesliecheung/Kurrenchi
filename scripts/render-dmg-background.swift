#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: render-dmg-background.swift <input> <output>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: inputURL) else {
    fputs("Unable to load source image.\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: 900, height: 560)
let canvas = NSImage(size: canvasSize)
canvas.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(
    in: NSRect(origin: .zero, size: canvasSize),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1
)

func centeredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: 0.2
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    attributed.draw(in: NSRect(x: 70, y: y, width: 760, height: 52))
}

centeredText(
    "Kurrenchi",
    y: 482,
    font: NSFont.systemFont(ofSize: 31, weight: .semibold),
    color: NSColor.black.withAlphaComponent(0.88)
)
centeredText(
    "将 Kurrenchi 拖入 Applications 文件夹",
    y: 444,
    font: NSFont.systemFont(ofSize: 16, weight: .medium),
    color: NSColor.black.withAlphaComponent(0.62)
)
centeredText(
    "拖放即可安装  ·  安装后从菜单栏使用",
    y: 41,
    font: NSFont.systemFont(ofSize: 14, weight: .regular),
    color: NSColor.black.withAlphaComponent(0.50)
)

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode background.\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)

