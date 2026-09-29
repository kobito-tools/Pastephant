import AppKit

// SVG を指定の大きさの PNG にする（macOS の SVG 描画を使う）。使い方: render-svg.swift <入力.svg> <出力.png> <幅> [高さ（省略すると幅と同じ）]
let input = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
let pixels = Int(CommandLine.arguments[3]) ?? 1024
let height = CommandLine.arguments.count > 4 ? Int(CommandLine.arguments[4]) ?? pixels : pixels
guard let image = NSImage(contentsOf: input) else { fatalError("SVG を読めません: \(input.path)") }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: height))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
