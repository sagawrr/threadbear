import AppKit

/// The mascot's shapes: an original chibi girl with twin tails, drawn as
/// line glyphs on a 24 by 24 grid (y down), in place of the bear this fork
/// started with. Bear.swift draws the still poses from these and
/// WavingBearView cuts the waving one into layers it can move, so the two
/// can't drift apart (BearTests compares them).
///
/// She's nobody's character: drawn here from circles and curves, so the
/// repo carries no one else's art. Pictures of characters you like go in
/// as a wallpaper, from your own files (Appearance.swift).
enum Mascot {
    /// One pose, as paths on the grid.
    struct Figure {
        /// The face's outline. Stroked.
        var head: CGPath
        /// The twin tails. Stroked, and shown only outside `head` so the
        /// outlines don't cross.
        var tails: CGPath
        /// The parting and the lock of hair on top. Stroked.
        var fringe: CGPath
        /// Open eyes are filled; shut ones are stroked curves.
        var eyes: CGPath
        var eyesShut = false
        /// A small smile. Stroked.
        var mouth: CGPath
        /// The dress under a sitting figure. Stroked, outside `head`.
        var body: CGPath?
        /// The collar on the dress. Stroked.
        var collar: CGPath?
        /// The raised arm and its hand. Stroked.
        var arm: CGPath?
        var hand: CGPath?
        /// The Zs over a sleeping figure. Stroked, thinner.
        var extras: CGPath?
        /// Where the eyes sit, for a blink to squash them about.
        var eyeLine: CGPoint
        /// Under the chin, for the figure to pop up and breathe from.
        var feet: CGPoint
    }

    /// Lines are a twelfth of the side or so, round-capped: the weight of
    /// an SF Symbol at the same size.
    static let lineWidth: CGFloat = 1.6

    /// The waving pose's measurements, shared with WavingBearView.
    enum Wave {
        static let headCentre = CGPoint(x: 9.8, y: 13.4)
        static let headRadius: CGFloat = 6.2
        /// Where the arm leaves the head; the hand swings about this.
        static let shoulder = CGPoint(x: 15.0, y: 16.9)
        static let armEnd = CGPoint(x: 20.8, y: 10.2)
        static let armControl1 = CGPoint(x: 19.2, y: 16.6)
        static let armControl2 = CGPoint(x: 21.6, y: 13.6)
        static let hand = CGPoint(x: 20.9, y: 7.7)
        static let handRadius: CGFloat = 2.3
    }

    static func figure(_ pose: Bear.Pose) -> Figure {
        switch pose {
        case .wave:
            // The tail on the waving side is kept short, clear of the arm.
            var f = face(centre: Wave.headCentre, radius: Wave.headRadius, tails: 1, rightTail: 0.35)
            let arm = CGMutablePath()
            arm.move(to: Wave.shoulder)
            arm.addCurve(to: Wave.armEnd, control1: Wave.armControl1, control2: Wave.armControl2)
            f.arm = arm
            f.hand = CGPath(ellipseIn: circle(Wave.hand, Wave.handRadius), transform: nil)
            return f
        case .sleep:
            let c = CGPoint(x: 10, y: 14)
            var tilt = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: 12 * .pi / 180).translatedBy(x: -c.x, y: -c.y)
            let upright = face(centre: c, radius: 6.2, tails: 1, eyesShut: true)
            var f = upright
            f.head = upright.head.copy(using: &tilt) ?? upright.head
            f.tails = upright.tails.copy(using: &tilt) ?? upright.tails
            f.fringe = upright.fringe.copy(using: &tilt) ?? upright.fringe
            f.eyes = upright.eyes.copy(using: &tilt) ?? upright.eyes
            f.mouth = upright.mouth.copy(using: &tilt) ?? upright.mouth
            let zs = CGMutablePath()
            addZ(to: zs, at: CGPoint(x: 18.4, y: 6.6), size: 2.2)
            addZ(to: zs, at: CGPoint(x: 20.6, y: 1.8), size: 3)
            f.extras = zs
            return f
        case .sit, .cub:
            let cub = pose == .cub
            let r: CGFloat = cub ? 4.6 : 5
            let c = CGPoint(x: 12, y: cub ? 9.6 : 8)
            var f = face(centre: c, radius: r, tails: cub ? 0.8 : 1)
            // The dress: narrow under the chin, wide at a rounded hem.
            let neck = c.y + r - 0.6
            let hem: CGFloat = cub ? 20.4 : 21.4
            let half: CGFloat = cub ? 5.2 : 6.4
            let dress = CGMutablePath()
            dress.move(to: CGPoint(x: c.x - 2.4, y: neck))
            dress.addLine(to: CGPoint(x: c.x - half, y: hem))
            dress.addQuadCurve(to: CGPoint(x: c.x + half, y: hem), control: CGPoint(x: c.x, y: hem + 2.2))
            dress.addLine(to: CGPoint(x: c.x + 2.4, y: neck))
            f.body = dress
            // A sailor collar: a V under the chin.
            let collar = CGMutablePath()
            collar.move(to: CGPoint(x: c.x - 2.1, y: c.y + r + 0.9))
            collar.addLine(to: CGPoint(x: c.x, y: c.y + r + 3.4))
            collar.addLine(to: CGPoint(x: c.x + 2.1, y: c.y + r + 0.9))
            f.collar = collar
            f.feet = CGPoint(x: c.x, y: hem)
            return f
        }
    }

    /// A face: round head, a tail of hair each side, a parting, eyes and a
    /// smile. `tails` scales how far the hair reaches out.
    static func face(centre c: CGPoint, radius r: CGFloat, tails reach: CGFloat, rightTail: CGFloat? = nil, eyesShut: Bool = false) -> Figure {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * r, y: c.y + y * r) }

        let tails = CGMutablePath()
        for sign in [-1.0, 1.0] as [CGFloat] {
            // A teardrop from the side of the crown, out and down to a
            // point, and back in under it. Its inner edge is hidden by
            // the head.
            let out = sign > 0 ? (rightTail ?? reach) : reach
            tails.move(to: at(sign * 0.55, -0.86))
            tails.addCurve(to: at(sign * (1.0 + 0.42 * out), 0.36 * out + 0.1),
                           control1: at(sign * (1.0 + 0.2 * out), -1.16),
                           control2: at(sign * (1.0 + 0.62 * out), -0.36))
            tails.addCurve(to: at(sign * 0.98, -0.12),
                           control1: at(sign * (1.0 + 0.3 * out), 0.2),
                           control2: at(sign * (1.0 + 0.12 * out), 0.02))
        }

        // The parting: from a point left of the crown, one sweep across
        // the forehead to the right and a shorter one to the left.
        let fringe = CGMutablePath()
        fringe.move(to: at(-0.22, -0.99))
        fringe.addCurve(to: at(0.95, -0.3), control1: at(-0.3, -0.38), control2: at(0.35, -0.2))
        fringe.move(to: at(-0.22, -0.99))
        fringe.addCurve(to: at(-0.96, -0.24), control1: at(-0.42, -0.62), control2: at(-0.7, -0.38))
        // A lock that stands up on top.
        fringe.move(to: at(0.02, -1.0))
        fringe.addQuadCurve(to: at(0.5, -1.34), control: at(0.1, -1.46))

        let eyeY: CGFloat = 0.16
        let eyes = CGMutablePath()
        for sign in [-1.0, 1.0] as [CGFloat] {
            if eyesShut {
                eyes.move(to: at(sign * 0.42 - 0.2, eyeY - 0.02))
                eyes.addCurve(to: at(sign * 0.42 + 0.2, eyeY - 0.02),
                              control1: at(sign * 0.42 - 0.1, eyeY + 0.2),
                              control2: at(sign * 0.42 + 0.1, eyeY + 0.2))
            } else {
                eyes.addEllipse(in: CGRect(x: c.x + (sign * 0.42 - 0.14) * r, y: c.y + (eyeY - 0.21) * r, width: 0.28 * r, height: 0.42 * r))
            }
        }

        let mouth = CGMutablePath()
        mouth.move(to: at(-0.15, 0.56))
        mouth.addQuadCurve(to: at(0.15, 0.56), control: at(0, 0.72))

        return Figure(head: CGPath(ellipseIn: circle(c, r), transform: nil), tails: tails, fringe: fringe,
                      eyes: eyes, eyesShut: eyesShut, mouth: mouth,
                      eyeLine: at(0, eyeY), feet: at(0, 1))
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    }

    private static func addZ(to path: CGMutablePath, at origin: CGPoint, size: CGFloat) {
        path.move(to: origin)
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + size))
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y + size))
    }

    /// Draws a pose into the current context, which is already scaled to
    /// the grid, in the current fill and stroke colour.
    static func draw(_ figure: Figure, in context: CGContext) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        func stroke(_ path: CGPath?, width: CGFloat = lineWidth) {
            guard let path else { return }
            context.addPath(path)
            context.setLineWidth(width)
            context.strokePath()
        }
        // Hair and dress first, clipped to outside the head.
        context.saveGState()
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: -10, y: -10, width: 44, height: 44))
        outside.addPath(figure.head)
        context.addPath(outside)
        context.clip(using: .evenOdd)
        stroke(figure.tails)
        stroke(figure.body)
        context.restoreGState()
        stroke(figure.head)
        stroke(figure.fringe, width: lineWidth * 0.85)
        if figure.eyesShut {
            stroke(figure.eyes, width: lineWidth * 0.85)
        } else {
            context.addPath(figure.eyes)
            context.fillPath()
        }
        stroke(figure.mouth, width: lineWidth * 0.7)
        stroke(figure.collar, width: lineWidth * 0.8)
        stroke(figure.arm)
        stroke(figure.hand)
        stroke(figure.extras, width: lineWidth * 0.85)
        context.restoreGState()
    }

    // MARK: Cards

    @MainActor private static var cards: [Bear.Pose: NSImage] = [:]

    /// The mascot on a soft card in the accent colour, with a few
    /// sparkles: the picture at the top of a page when you haven't set
    /// one of your own. Drawn when shown, so it follows light and dark.
    @MainActor
    static func card(_ pose: Bear.Pose) -> NSImage {
        if let cached = cards[pose] { return cached }
        let size = NSSize(width: 260, height: 200)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemPink
            let tile = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 26, cornerHeight: 26, transform: nil)
            context.saveGState()
            context.addPath(tile)
            context.clip()
            let colours = [accent.withAlphaComponent(0.30).cgColor, accent.withAlphaComponent(0.08).cgColor] as CFArray
            if let wash = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours, locations: [0, 1]) {
                context.drawLinearGradient(wash, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            }
            context.restoreGState()
            context.addPath(tile)
            context.setStrokeColor(accent.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(1)
            context.strokePath()

            context.setFillColor(accent.withAlphaComponent(0.75).cgColor)
            for (x, y, r) in [(46.0, 44.0, 9.0), (214.0, 62.0, 12.0), (196.0, 150.0, 7.0), (64.0, 156.0, 6.0)] as [(CGFloat, CGFloat, CGFloat)] {
                context.addPath(sparkle(at: CGPoint(x: x, y: y), radius: r))
                context.fillPath()
            }

            let side: CGFloat = 132
            context.saveGState()
            context.translateBy(x: rect.midX - side / 2, y: rect.midY - side / 2)
            context.scaleBy(x: side / 24, y: side / 24)
            context.setFillColor(accent.cgColor)
            context.setStrokeColor(accent.cgColor)
            draw(figure(pose), in: context)
            context.restoreGState()
            return true
        }
        image.accessibilityDescription = Bear.description(pose)
        cards[pose] = image
        return image
    }

    /// A four-pointed star with pinched sides.
    static func sparkle(at c: CGPoint, radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let pinch = r * 0.22
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
        path.closeSubpath()
        return path
    }
}
