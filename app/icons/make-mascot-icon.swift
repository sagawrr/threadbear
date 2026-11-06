// Makes app/icons/threadbear.png for this fork: the mascot (Mascot.swift) in
// white on a sakura-to-violet tile, drawn in code so the repo carries no
// one else's art. From the repo's root:
//
//   swiftc -O -o /tmp/make-mascot-icon app/icons/make-mascot-icon.swift app/Sources/Threadbear/Mascot.swift
//   /tmp/make-mascot-icon app/icons/threadbear.png
//
// build-app.sh turns that PNG into the app's .icns. Upstream's
// make-icon.swift beside this one cuts the icon out of a painted mascot.
import AppKit

// Mascot.swift is the app's; these are the two things it asks of Bear.
enum Bear {
    enum Pose: String, CaseIterable { case sit, wave, sleep, cub }
    static func description(_ pose: Pose) -> String { pose.rawValue }
}

@main
enum MakeMascotIcon {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write("usage: make-mascot-icon <out.png>\n".data(using: .utf8)!)
            exit(1)
        }
        // The usual icon tile: 824 of 1024 points, corners about 22.37% of
        // its side, y down like the mascot's grid.
        let canvas: CGFloat = 1024, side: CGFloat = 824, margin = (canvas - side) / 2
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: canvas)
        ctx.scaleBy(x: 1, y: -1)
        let tile = CGRect(x: margin, y: margin, width: side, height: side)
        let radius = side * 0.2237
        let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

        func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
        }

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        // Sakura at the top left, through to violet at the bottom right.
        let wash = CGGradient(colorsSpace: space, colors: [colour(255, 158, 196), colour(236, 112, 178), colour(132, 102, 240)] as CFArray,
                              locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(wash, start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
        // A soft light from above.
        let glow = CGGradient(colorsSpace: space, colors: [colour(255, 255, 255, 0.38), colour(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.midX - 120, y: tile.minY + 90), startRadius: 0,
                               endCenter: CGPoint(x: tile.midX - 120, y: tile.minY + 90), endRadius: 560, options: [])

        ctx.setFillColor(colour(255, 255, 255, 0.85))
        for (x, y, r) in [(250.0, 268.0, 44.0), (790.0, 300.0, 58.0), (760.0, 740.0, 34.0), (236.0, 716.0, 28.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.addPath(Mascot.sparkle(at: CGPoint(x: x, y: y), radius: r))
            ctx.fillPath()
        }

        // The mascot, sat, with a soft shadow under her lines.
        let figure: CGFloat = 600
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: colour(96, 40, 120, 0.35))
        ctx.translateBy(x: tile.midX - figure / 2, y: tile.midY - figure / 2 + 6)
        ctx.scaleBy(x: figure / 24, y: figure / 24)
        ctx.setFillColor(colour(255, 255, 255))
        ctx.setStrokeColor(colour(255, 255, 255))
        Mascot.draw(Mascot.figure(.sit), in: ctx)
        ctx.restoreGState()
        ctx.restoreGState()

        // A hairline round the tile, as system icons have.
        ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius - 1.5, cornerHeight: radius - 1.5, transform: nil))
        ctx.setStrokeColor(colour(255, 255, 255, 0.28))
        ctx.setLineWidth(3)
        ctx.strokePath()

        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("wrote \(CommandLine.arguments[1]) \(Int(canvas))x\(Int(canvas))")
    }
}
