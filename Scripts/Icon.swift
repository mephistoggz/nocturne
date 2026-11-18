import AppKit

// Six sizes share a single vector master. The staggered ribbons form an N.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = base * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let c = gc.cgContext
    c.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    let rect = CGRect(x: 85, y: 77, width: 854, height: 854)
    let back = NSBezierPath(roundedRect: rect, xRadius: 192, yRadius: 192)
    NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.025, alpha: 1))!
      .draw(in: back, angle: -70)
    NSColor(white: 0.28, alpha: 1).setStroke()
    back.lineWidth = 4
    back.stroke()
    let gradient = NSGradient(colors: [
      NSColor(white: 0.52, alpha: 1), NSColor(white: 0.97, alpha: 1),
      NSColor(white: 0.59, alpha: 1),
    ])!
    for (i, h) in [210, 328, 430, 340, 255, 368].enumerated() {
      let x = 283 + 77 * i
      let y = [330, 320, 294, 333, 370, 340][i]
      let path = NSBezierPath(
        roundedRect: NSRect(x: x, y: y, width: 51, height: h), xRadius: 25, yRadius: 25)
      gradient.draw(in: path, angle: 58)
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
  }
}
