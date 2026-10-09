// Generates the app icon (a ridge line at night with one signal flare) into the asset catalog.
// Usage: swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = s * 0.098
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // night sky gradient
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [CGColor(red: 0.10, green: 0.13, blue: 0.19, alpha: 1), CGColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    // stars
    let stars: [(CGFloat, CGFloat, CGFloat)] = [(0.22, 0.80, 0.006), (0.38, 0.86, 0.004), (0.63, 0.82, 0.005), (0.80, 0.74, 0.004), (0.30, 0.68, 0.003), (0.72, 0.90, 0.003)]
    ctx.setFillColor(CGColor(red: 0.85, green: 0.90, blue: 1, alpha: 0.7))
    for (x, y, r) in stars { ctx.fillEllipse(in: CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height, width: r * s, height: r * s)) }
    // far ridge
    func ridge(_ pts: [(CGFloat, CGFloat)], _ color: CGColor) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for (x, y) in pts { p.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(color)
        ctx.fillPath()
    }
    ridge([(0, 0.42), (0.18, 0.55), (0.33, 0.47), (0.52, 0.66), (0.70, 0.50), (0.86, 0.58), (1, 0.48)], CGColor(red: 0.20, green: 0.26, blue: 0.35, alpha: 1))
    ridge([(0, 0.30), (0.22, 0.38), (0.45, 0.27), (0.62, 0.36), (0.80, 0.25), (1, 0.33)], CGColor(red: 0.62, green: 0.70, blue: 0.80, alpha: 1))
    ridge([(0, 0.17), (0.30, 0.22), (0.55, 0.15), (0.78, 0.20), (1, 0.14)], CGColor(red: 0.86, green: 0.90, blue: 0.95, alpha: 1))
    // the flare: glow + core
    let fc = CGPoint(x: rect.minX + 0.66 * rect.width, y: rect.minY + 0.72 * rect.height)
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 1, green: 0.62, blue: 0.24, alpha: 0.85), CGColor(red: 1, green: 0.45, blue: 0.15, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: fc, startRadius: 0, endCenter: fc, endRadius: rect.width * 0.20, options: [])
    ctx.setFillColor(CGColor(red: 1, green: 0.86, blue: 0.62, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: fc.x - s * 0.018, y: fc.y - s * 0.018, width: s * 0.036, height: s * 0.036))
    // flare trail
    ctx.setStrokeColor(CGColor(red: 1, green: 0.62, blue: 0.24, alpha: 0.55))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.move(to: CGPoint(x: fc.x - rect.width * 0.02, y: fc.y - rect.height * 0.03))
    ctx.addCurve(to: CGPoint(x: rect.minX + 0.50 * rect.width, y: rect.minY + 0.30 * rect.height),
                 control1: CGPoint(x: fc.x - rect.width * 0.05, y: fc.y - rect.height * 0.15),
                 control2: CGPoint(x: rect.minX + 0.52 * rect.width, y: rect.minY + 0.42 * rect.height))
    ctx.strokePath()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for sc in scales {
        let name = "icon_\(pt)x\(pt)@\(sc)x.png"
        try! draw(pt * sc).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(sc)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
try! data.write(to: outDir.appendingPathComponent("Contents.json"))
print("icon written to \(outDir.path)")
