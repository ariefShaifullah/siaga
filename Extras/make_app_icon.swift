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

// Dark mode: transparent, iOS supplies the dark backdrop.
save(heart, "AppIcon-Dark.png")

// Light mode: same look on an opaque dark gradient (App Store icons must not have alpha).
let any = context(opaque: true)
any.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(0x2C2C2E), rgb(0x0B0B0C)] as CFArray, locations: nil)!,
                       start: .zero, end: CGPoint(x: 0, y: size), options: [])
any.scaleBy(x: 1, y: -1); any.translateBy(x: 0, y: -size) // back to CG's bottom-left origin, or draw() flips the image
any.draw(heart, in: CGRect(x: 0, y: 0, width: size, height: size))
save(any.makeImage()!, "AppIcon.png")
