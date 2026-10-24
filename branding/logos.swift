// logos.swift — renders Strike Pro OSS replacements for the editor's logo sprites and app icon.
// Usage: swift branding/logos.swift <Resources dir> <iconset output dir>
//
// Sprite regions are defined in the editor's Skins.xml and must keep their geometry:
//   productLogos.png        658x290  PresetEditor.Logos.Alesis           (30,20)  535x95
//                                    PresetEditor.Logos.Strike.White     (32,141) 592x144
//   Alesis_strike_logo.png  308x32   PresetEditor.Logos.AlesisStrikeLogo (0,0)    308x32

import AppKit

let blue = NSColor(srgbRed: 0, green: 147 / 255, blue: 208 / 255, alpha: 1)
let light = NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 244 / 255, alpha: 1)
let dark = NSColor(srgbRed: 28 / 255, green: 30 / 255, blue: 34 / 255, alpha: 1)
let fontName = "Futura-CondensedExtraBold"

func canvas(_ w: Int, _ h: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    // Flip so rects below use a top-left origin, matching Skins.xml coordinates.
    ctx.cgContext.translateBy(x: 0, y: CGFloat(h))
    ctx.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Draws slanted text runs scaled to fill `rect` (top-left origin), centred or left-aligned.
func slanted(_ runs: [(String, NSColor)], in rect: CGRect, center: Bool = true) {
    func attributed(_ size: CGFloat) -> NSAttributedString {
        let s = NSMutableAttributedString()
        for (text, color) in runs {
            s.append(NSAttributedString(string: text, attributes: [
                .font: NSFont(name: fontName, size: size)!, .foregroundColor: color, .kern: size * 0.02,
            ]))
        }
        return s
    }
    let skew: CGFloat = 0.22
    var size = rect.height * 1.2
    var str = attributed(size)
    while size > 4 {
        let b = str.size()
        if b.width + b.height * skew <= rect.width && b.height * 0.78 <= rect.height { break }
        size -= 0.5
        str = attributed(size)
    }
    let b = str.size()
    let font = NSFont(name: fontName, size: size)!
    let x = center ? rect.minX + (rect.width - b.width - b.height * skew) / 2 : rect.minX
    let baseline = rect.midY + font.capHeight / 2
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: x, y: baseline)
    ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: -skew, d: 1, tx: 0, ty: 0))
    str.draw(at: NSPoint(x: 0, y: -font.ascender))
    ctx.restoreGState()
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

/// Renders the two logo sprite sheets into `resources`, keeping the original file names and sizes.
func renderLogos(into resources: String) {
    save(canvas(658, 290) {
        slanted([("STRIKE PRO", blue)], in: CGRect(x: 30, y: 20, width: 535, height: 95))
        slanted([("OSS", light)], in: CGRect(x: 32, y: 141, width: 592, height: 144))
    }, "\(resources)/productlogos.png")

    save(canvas(308, 32) {
        slanted([("STRIKE PRO ", blue), ("OSS", light)], in: CGRect(x: 2, y: 3, width: 304, height: 26), center: false)
    }, "\(resources)/alesis_strike_logo.png")
}

/// App icon at `px` pixels: dark rounded tile with a blue ring, blue "SP", light "OSS" (omitted when tiny).
func renderIcon(px: Int) -> NSBitmapImageRep {
    let f = CGFloat(px) / 1024
    return canvas(px, px) {
        let tile = CGRect(x: 100 * f, y: 100 * f, width: 824 * f, height: 824 * f)
        dark.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 185 * f, yRadius: 185 * f).fill()
        blue.setStroke()
        let ring = NSBezierPath(roundedRect: tile.insetBy(dx: 26 * f, dy: 26 * f), xRadius: 160 * f, yRadius: 160 * f)
        ring.lineWidth = 18 * f
        ring.stroke()
        slanted([("SP", blue)], in: CGRect(x: 180 * f, y: 230 * f, width: 664 * f, height: 380 * f))
        if px >= 64 {
            slanted([("OSS", light)], in: CGRect(x: 280 * f, y: 650 * f, width: 464 * f, height: 130 * f))
        }
    }
}

/// Writes every size iconutil expects into `iconset`.
func renderIconset(into iconset: String) {
    try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            save(renderIcon(px: pt * scale), "\(iconset)/icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png")
        }
    }
}

// Tests load this file with STRIKE_TEST set and call the functions directly.
if ProcessInfo.processInfo.environment["STRIKE_TEST"] == nil {
    renderLogos(into: CommandLine.arguments[1])
    renderIconset(into: CommandLine.arguments[2])
}
