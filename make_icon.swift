//
//  make_icon.swift — Zeichnet das Schelf-App-Icon (1024×1024 PNG) via CoreGraphics.
//  Aufruf:  swift make_icon.swift Resources/icon-source.png
//
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("Nutzung: swift make_icon.swift <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let outURL = URL(fileURLWithPath: args[1])

let size: CGFloat = 1024
let px = Int(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: px, height: px,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(2) }

func rrect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let full = CGRect(x: 0, y: 0, width: size, height: size)
let iconRect = full
let radius: CGFloat = size * 0.2237

// 1) Squircle-Hintergrund mit Verlauf (Indigo → Blau).
let path = rrect(iconRect, radius: radius)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()

let colors = [
    CGColor(red: 0.16, green: 0.22, blue: 0.62, alpha: 1.0),
    CGColor(red: 0.23, green: 0.47, blue: 0.95, alpha: 1.0)
] as [CGColor]
let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0.0, 1.0])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0), options: [])

ctx.setShadow(offset: .zero, blur: 60, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
ctx.fillEllipse(in: iconRect.insetBy(dx: size*0.18, dy: size*0.18))
ctx.restoreGState()

// 2) Schwebendes Tray (weiß, geschichtet — "Ablage").
ctx.saveGState()
let trayW = size * 0.52
let trayH = size * 0.14
let cx = size * 0.5
let cy = size * 0.42

let back = CGRect(x: cx - trayW/2, y: cy, width: trayW, height: trayH)
ctx.addPath(rrect(back, radius: trayH*0.28))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
ctx.fillPath()

let front = CGRect(x: cx - trayW/2, y: cy - trayH*1.05, width: trayW, height: trayH)
ctx.addPath(rrect(front, radius: trayH*0.28))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
ctx.fillPath()

let base = CGRect(x: cx - trayW*0.40, y: cy - trayH*1.45, width: trayW*0.80, height: trayH*0.45)
ctx.addPath(rrect(base, radius: trayH*0.2))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
ctx.fillPath()
ctx.restoreGState()

// 3) Pfeil nach unten (in den Tray).
ctx.saveGState()
let arrowTop = size * 0.70
let arrowBottom = size * 0.52
let shaftW = size * 0.07
let headW = size * 0.20

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
ctx.addPath(rrect(CGRect(x: cx - shaftW/2, y: arrowBottom,
                         width: shaftW, height: arrowTop - arrowBottom), radius: shaftW*0.3))
ctx.fillPath()
ctx.beginPath()
ctx.move(to: CGPoint(x: cx - headW/2, y: arrowBottom + headW*0.5))
ctx.addLine(to: CGPoint(x: cx + headW/2, y: arrowBottom + headW*0.5))
ctx.addLine(to: CGPoint(x: cx, y: arrowBottom))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

guard let img = ctx.makeImage() else { exit(3) }
let bitmap = NSBitmapImageRep(cgImage: img)
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
try! png.write(to: outURL)
print("✅ Icon geschrieben: \(outURL.path)")
