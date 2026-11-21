// Regenerates the PNGs in siaga/Assets.xcassets/AppIcon.appiconset/.
// Run from the repo root: swift Extras/make_app_icon.swift
import AppKit

let size = 1024.0, sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func context(opaque: Bool) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1) // top-left origin
    return ctx
}
func save(_ image: CGImage, _ name: String) {
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "siaga/Assets.xcassets/AppIcon.appiconset/\(name)"))
}

// Red heart with the pulse line punched out, on transparency.
let glyph = context(opaque: false)
// Heart: a square rotated 45° plus two circles on its upper edges.
let d = 500.0, cx = 512.0, cy = 535.0, r = d / (2 * 2.0.squareRoot())
glyph.setFillColor(rgb(0xDC2626))
glyph.move(to: CGPoint(x: cx, y: cy - d/2)); glyph.addLine(to: CGPoint(x: cx + d/2, y: cy))
glyph.addLine(to: CGPoint(x: cx, y: cy + d/2)); glyph.addLine(to: CGPoint(x: cx - d/2, y: cy)); glyph.closePath()
for dx in [-d/4, d/4] { glyph.addEllipse(in: CGRect(x: cx + dx - r, y: cy - d/4 - r, width: 2*r, height: 2*r)) }
glyph.fillPath()
let y = cy - 30
glyph.setBlendMode(.clear); glyph.setLineWidth(42); glyph.setLineCap(.round); glyph.setLineJoin(.round)
glyph.addLines(between: [(150, y), (370, y), (430, y - 70), (490, y + 150), (560, y - 190), (620, y + 40), (650, y), (874, y)]
    .map { CGPoint(x: $0.0, y: $0.1) })
glyph.strokePath()
let heart = glyph.makeImage()!

// Light mode: same look on an opaque dark gradient (App Store icons must not have alpha).
let any = context(opaque: true)
any.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(0x2C2C2E), rgb(0x0B0B0C)] as CFArray, locations: nil)!,
                       start: .zero, end: CGPoint(x: 0, y: size), options: [])
any.scaleBy(x: 1, y: -1); any.translateBy(x: 0, y: -size) // back to CG's bottom-left origin, or draw() flips the image
any.draw(heart, in: CGRect(x: 0, y: 0, width: size, height: size))
let light = any.makeImage()!

// Xcode's iOS "All Sizes" list: (points, scales). 1024 is the App Store marketing icon.
let sizes: [(Double, [Int])] = [(20, [2, 3]), (29, [2, 3]), (38, [2, 3]), (40, [2, 3]), (60, [2, 3]),
                                (64, [2, 3]), (68, [2]), (76, [2]), (83.5, [2]), (1024, [1])]
var entries: [[String: Any]] = []
for (points, scales) in sizes {
    for scale in scales {
        let label = points.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(points)) : String(points)
        let px = Int(points * Double(scale))
        // Dark mode: transparent, iOS supplies the dark backdrop.
        for (image, dark) in [(light, false), (heart, true)] {
            let name = "AppIcon\(dark ? "-Dark" : "")" + (scale == 1 ? "" : "-\(label)@\(scale)x") + ".png"
            let small = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: (dark ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
            small.interpolationQuality = .high
            small.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
            save(small.makeImage()!, name)
            var entry: [String: Any] = ["filename": name, "idiom": "universal", "platform": "ios", "size": "\(label)x\(label)"]
            if scale != 1 { entry["scale"] = "\(scale)x" }
            if dark { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
            entries.append(entry)
        }
    }
}
let json = try! JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]],
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "siaga/Assets.xcassets/AppIcon.appiconset/Contents.json"))
