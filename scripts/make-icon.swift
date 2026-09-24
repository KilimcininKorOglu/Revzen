// Renders the Revzen app icon from the dock.rectangle SF Symbol.
// Usage: swift scripts/make-icon.swift <output.png>
// The Makefile turns the 1024 px PNG into Resources/AppIcon.icns.
import AppKit

let size: CGFloat = 1024
// The macOS icon grid: an 824 pt rounded square centered on a 1024 pt canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep)
else {
    fatalError("cannot create the bitmap context")
}
NSGraphicsContext.current = context

let shape = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)
let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.29, green: 0.47, blue: 0.98, alpha: 1),
    ending: NSColor(srgbRed: 0.16, green: 0.22, blue: 0.62, alpha: 1)
)
gradient?.draw(in: shape, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard
    let symbol = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
else {
    fatalError("the dock.rectangle symbol is not available")
}
let symbolRect = NSRect(
    x: tile.midX - symbol.size.width / 2,
    y: tile.midY - symbol.size.height / 2,
    width: symbol.size.width,
    height: symbol.size.height
)
symbol.draw(in: symbolRect)

NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode the icon as PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
