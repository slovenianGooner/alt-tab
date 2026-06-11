import Cocoa

// Draw the AltTab icon at a given size into a CGContext
func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    defer { img.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

    let r = s * 0.13  // corner radius of the two window cards

    // --- Background: deep dark rounded square ---
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor)
    ctx.addPath(bgPath)
    ctx.fillPath()

    // --- Back window card (slightly offset top-left) ---
    let backRect = CGRect(x: s * 0.16, y: s * 0.30, width: s * 0.54, height: s * 0.38)
    let backPath = CGPath(roundedRect: backRect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.setFillColor(NSColor(srgbRed: 0.30, green: 0.30, blue: 0.36, alpha: 1).cgColor)
    ctx.addPath(backPath)
    ctx.fillPath()
    // subtle stroke
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(s * 0.018)
    ctx.addPath(backPath)
    ctx.strokePath()

    // --- Front window card (offset down-right, brighter) ---
    let frontRect = CGRect(x: s * 0.30, y: s * 0.20, width: s * 0.54, height: s * 0.38)
    let frontPath = CGPath(roundedRect: frontRect, cornerWidth: r, cornerHeight: r, transform: nil)
    // gradient fill for the front card
    ctx.saveGState()
    ctx.addPath(frontPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(srgbRed: 0.42, green: 0.55, blue: 1.0, alpha: 1).cgColor,
            NSColor(srgbRed: 0.28, green: 0.38, blue: 0.90, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: frontRect.minX, y: frontRect.maxY),
        end:   CGPoint(x: frontRect.maxX, y: frontRect.minY),
        options: [])
    ctx.restoreGState()

    // window titlebar line on front card
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    let titleBarH = s * 0.07
    let titleBarRect = CGRect(x: frontRect.minX, y: frontRect.maxY - titleBarH,
                              width: frontRect.width, height: titleBarH)
    let titleBarClip = CGPath(roundedRect: CGRect(
        x: frontRect.minX, y: frontRect.minY,
        width: frontRect.width, height: frontRect.height),
        cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.saveGState()
    ctx.addPath(titleBarClip)
    ctx.clip()
    ctx.fill(titleBarRect)
    ctx.restoreGState()

    // --- Arrow: ⇥ shape, bottom-right area ---
    let arrowCX = s * 0.73
    let arrowCY = s * 0.28
    let aw = s * 0.15   // arrow body half-width
    let ah = s * 0.04   // arrow body half-height
    let headW = s * 0.07
    let headH = s * 0.10

    let arrow = CGMutablePath()
    // body
    arrow.addRect(CGRect(x: arrowCX - aw, y: arrowCY - ah, width: aw * 1.4, height: ah * 2))
    // head
    arrow.move(to: CGPoint(x: arrowCX + aw * 0.4, y: arrowCY + headH))
    arrow.addLine(to: CGPoint(x: arrowCX + aw * 0.4 + headW, y: arrowCY))
    arrow.addLine(to: CGPoint(x: arrowCX + aw * 0.4, y: arrowCY - headH))
    arrow.closeSubpath()

    ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.addPath(arrow)
    ctx.fillPath()

    return img
}

// Build iconset directory
let fm = FileManager.default
let iconsetPath = "/Users/papezl/Dev/alt-tab/AltTab/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
func pngData(from img: NSImage) -> Data {
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not produce PNG")
    }
    return png
}

for size in sizes {
    let img = drawIcon(size: size)
    let data = pngData(from: img)
    let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    try! data.write(to: URL(fileURLWithPath: iconsetPath + "/" + name))
    if [32, 64, 256, 512].contains(size) {
        let name2x = "icon_\(size/2)x\(size/2)@2x.png"
        try! data.write(to: URL(fileURLWithPath: iconsetPath + "/" + name2x))
    }
}

print("Iconset written to \(iconsetPath)")
