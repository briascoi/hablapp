// Ícono propio: squircle oscuro con barras de onda en crema y una barra naranja.
import Cocoa

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.17, green: 0.15, blue: 0.13, alpha: 1),
                    NSColor(srgbRed: 0.09, green: 0.08, blue: 0.08, alpha: 1)])!.draw(in: bg, angle: -90)
let heights = [0.18, 0.34, 0.56, 0.42, 0.66, 0.38, 0.22]
let w = 54.0, gap = 34.0
let total = Double(heights.count) * w + Double(heights.count - 1) * gap
for (i, h) in heights.enumerated() {
    let bh = rect.height * h
    let x = rect.midX - total / 2 + Double(i) * (w + gap)
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - bh / 2, width: w, height: bh), xRadius: w / 2, yRadius: w / 2)
    (i == 4 ? NSColor(srgbRed: 0.96, green: 0.65, blue: 0.28, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.94, blue: 0.90, alpha: 1)).setFill()
    bar.fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
