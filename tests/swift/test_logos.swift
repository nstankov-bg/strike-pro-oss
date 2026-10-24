// Tests for branding/logos.swift.

/// Alpha of pixel (x, y) with a top-left origin.
func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }

func opaquePixels(_ rep: NSBitmapImageRep, inside rect: CGRect, _ want: Bool) -> Int {
    var n = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where rect.contains(CGPoint(x: x, y: y)) == want && alpha(rep, x, y) > 0.1 {
            n += 1
        }
    }
    return n
}

func test_canvas() {
    var drew = false
    let rep = canvas(40, 20) {
        drew = true
        NSColor.red.setFill()
        CGRect(x: 0, y: 0, width: 10, height: 5).fill()  // top-left corner in canvas coordinates
    }
    expect(drew, "draw closure not called")
    expect(rep.pixelsWide == 40 && rep.pixelsHigh == 20, "size \(rep.pixelsWide)x\(rep.pixelsHigh)")
    expect(alpha(rep, 2, 2) > 0.9, "top-left should be filled (flipped coordinates)")
    expect(alpha(rep, 2, 17) == 0, "bottom-left should stay transparent")
}

func test_slanted() {
    let box = CGRect(x: 20, y: 10, width: 200, height: 40)
    let rep = canvas(240, 60) { slanted([("STRIKE", blue), (" PRO", light)], in: box) }
    expect(opaquePixels(rep, inside: box, true) > 500, "text should be drawn inside the box")
    expect(opaquePixels(rep, inside: box.insetBy(dx: -2, dy: -2), false) == 0, "text must stay inside its box")
    let left = canvas(240, 60) { slanted([("OSS", blue)], in: box, center: false) }
    let centered = canvas(240, 60) { slanted([("OSS", blue)], in: box) }
    expect(opaquePixels(left, inside: CGRect(x: 20, y: 10, width: 30, height: 40), true) >
           opaquePixels(centered, inside: CGRect(x: 20, y: 10, width: 30, height: 40), true), "left-aligned text starts at the left edge")
}

func test_save() {
    let path = tempDir() + "/x.png"
    save(canvas(8, 4) { NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 8, height: 4).fill() }, path)
    let loaded = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data())
    expect(loaded?.pixelsWide == 8 && loaded?.pixelsHigh == 4, "PNG round trip")
}

func test_renderLogos() {
    let dir = tempDir()
    renderLogos(into: dir)
    for (name, w, h) in [("productlogos.png", 658, 290), ("alesis_strike_logo.png", 308, 32)] {
        let rep = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(name)"))) ?? Data())
        expect(rep?.pixelsWide == w && rep?.pixelsHigh == h, "\(name) must keep the sprite geometry \(w)x\(h)")
        if let rep {
            expect(opaquePixels(rep, inside: CGRect(x: 0, y: 0, width: w, height: h), true) > 1000, "\(name) is blank")
        }
    }
}

func test_renderIcon() {
    for px in [16, 64, 512] {
        let rep = renderIcon(px: px)
        expect(rep.pixelsWide == px && rep.pixelsHigh == px, "icon size \(px)")
        expect(alpha(rep, 0, 0) == 0, "corner of \(px)px icon should be transparent")
        expect(alpha(rep, px / 2, px / 2) > 0.9, "centre of \(px)px icon should be opaque")
    }
}

func test_renderIconset() {
    let dir = tempDir() + "/AppIcon.iconset"
    renderIconset(into: dir)
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    expect(files.count == 10, "expected 10 icon files, got \(files.count)")
    expect(files.contains("icon_512x512@2x.png") && files.contains("icon_16x16.png"), "iconutil naming")
}

test("test_canvas", test_canvas)
test("test_slanted", test_slanted)
test("test_save", test_save)
test("test_renderLogos", test_renderLogos)
test("test_renderIcon", test_renderIcon)
test("test_renderIconset", test_renderIconset)
finish()
