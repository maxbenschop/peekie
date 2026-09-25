import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: make-banner <icon.png> <output.png>\n".data(using: .utf8)!)
    exit(1)
}
guard let icon = NSImage(contentsOfFile: arguments[1]) else { exit(1) }

let width: CGFloat = 1280
let height: CGFloat = 640
let scale: CGFloat = 2

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: scale, y: scale)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [color(0x0E1014), color(0x1B1F27), color(0x262B36)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: canvas, angle: -35)

func glow(_ center: NSPoint, radius: CGFloat, _ tint: NSColor) {
    NSGradient(colors: [tint, tint.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}
glow(NSPoint(x: 1010, y: 330), radius: 460, color(0x3B82F6, 0.30))
glow(NSPoint(x: 1180, y: 560), radius: 340, color(0x8B5CF6, 0.24))
glow(NSPoint(x: 820, y: 60), radius: 300, color(0xFF9F0A, 0.12))

func bokeh(_ center: NSPoint, radius: CGFloat, fill: CGFloat, stroke: CGFloat) {
    let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    NSColor.white.withAlphaComponent(fill).setFill()
    path.fill()
    NSColor.white.withAlphaComponent(stroke).setStroke()
    path.lineWidth = 1
    path.stroke()
}
bokeh(NSPoint(x: 1215, y: 560), radius: 46, fill: 0.05, stroke: 0.14)
bokeh(NSPoint(x: 808, y: 120), radius: 30, fill: 0.04, stroke: 0.12)
bokeh(NSPoint(x: 1240, y: 96), radius: 64, fill: 0.04, stroke: 0.10)
bokeh(NSPoint(x: 900, y: 590), radius: 20, fill: 0.05, stroke: 0.14)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: point)
}

draw("Peekie", at: NSPoint(x: 88, y: 356), font: rounded(150, .heavy), color: .white, kern: -3)
draw("A translucent scratchpad for your Mac.", at: NSPoint(x: 94, y: 296), font: rounded(35, .medium), color: NSColor.white.withAlphaComponent(0.78))
draw("Peek through the glass. Write it. Let it go.", at: NSPoint(x: 94, y: 250), font: rounded(24, .regular), color: NSColor.white.withAlphaComponent(0.5))

var chipX: CGFloat = 94
for label in ["Global hotkey", "Frosted glass", "Code blocks", "Inline maths"] {
    let font = rounded(19, .semibold)
    let size = (label as NSString).size(withAttributes: [.font: font])
    let chip = NSRect(x: chipX, y: 150, width: size.width + 40, height: 44)
    let path = NSBezierPath(roundedRect: chip, xRadius: 22, yRadius: 22)
    NSColor.white.withAlphaComponent(0.08).setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.22).setStroke()
    path.lineWidth = 1
    path.stroke()
    draw(label, at: NSPoint(x: chipX + 20, y: 150 + (44 - size.height) / 2), font: font, color: NSColor.white.withAlphaComponent(0.9))
    chipX += chip.width + 12
}

draw("Free and open source  ·  macOS 14+  ·  MIT", at: NSPoint(x: 94, y: 92), font: rounded(19, .medium), color: NSColor.white.withAlphaComponent(0.42))

let iconSize: CGFloat = 430
let iconRect = NSRect(x: 812, y: 105, width: iconSize, height: iconSize)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 50
shadow.shadowOffset = NSSize(width: 0, height: -22)
NSGraphicsContext.saveGraphicsState()
shadow.set()
icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[2]))
