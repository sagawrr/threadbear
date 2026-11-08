import AppKit
import SwiftUI

/// The bear: Threadbear's mascot, drawn as line glyphs in code rather than
/// the PNG sprites it started with (docs/threadbear-design/sprites). At
/// sidebar and work-line sizes a painted sprite was a brown smudge; a
/// stroked outline reads at 16 pt and can be drawn at any size. The
/// images are templates, so they take the text colour around them like
/// an SF Symbol. One bear for the app, not one per thread. The drawing
/// itself is BearGeometry, shared with the iPhone app.
enum Bear {
    typealias Pose = BearGeometry.Pose

    /// The working line's bear, in points. A touch bigger than a 16 pt tool
    /// icon so it reads as a character, not a glyph.
    /// A picture of your own in the bear's place (Settings > Appearance)
    /// gets a little more room: a photo needs it more than a line glyph.
    @MainActor static var workingSide: CGFloat { TypeScale.scaled(Appearance.shared.mascot(.wave) == nil ? 26 : 30) }

    private static var cache: [String: NSImage] = [:]
    /// Which pictures `cache` was made from (Appearance.slotsVersion).
    private static var cachedPictures = 0

    /// The pose as a square template image `side` points across. The
    /// drawing is redone at whatever resolution it's shown at, so the
    /// lines stay crisp on any screen and at any zoom.
    @MainActor
    static func image(_ pose: Pose, side: CGFloat = 24, hat: Bool = BearGeometry.wearsHat(), pom: Bool = true) -> NSImage {
        if cachedPictures != Appearance.shared.slotsVersion {
            cache = [:]
            cachedPictures = Appearance.shared.slotsVersion
        }
        let key = "\(pose.rawValue)@\(side)\(hat ? "+hat" : "")\(pom ? "" : "-pom")"
        if let cached = cache[key] { return cached }
        if let picture = Appearance.shared.mascot(pose) {
            let image = portrait(picture, side: side)
            image.accessibilityDescription = description(pose)
            cache[key] = image
            return image
        }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(BearGeometry.inks(pose, side: side, hat: hat, pom: pom), in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(pose)
        cache[key] = image
        return image
    }

    /// A picture of your own in the bear's place, `side` points across and
    /// in its own colours: a cut-out character whole, a plain photo cropped
    /// to a circle with a hairline round it so it reads on any background.
    @MainActor
    static func portrait(_ picture: NSImage, side: CGFloat) -> NSImage {
        let cutOut = Appearance.isCutOut(picture)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            let fit = min(rect.width / picture.size.width, rect.height / picture.size.height)
            let fill = max(rect.width / picture.size.width, rect.height / picture.size.height)
            let scale = cutOut ? fit : fill
            let size = NSSize(width: picture.size.width * scale, height: picture.size.height * scale)
            let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            if cutOut {
                picture.draw(in: target)
            } else {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(ovalIn: rect).addClip()
                picture.draw(in: target)
                NSGraphicsContext.restoreGraphicsState()
                NSColor.separatorColor.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            }
            return true
        }
    }

    /// The pose for SwiftUI: the bear takes the text colour around it, a
    /// picture of your own keeps its colours.
    @MainActor
    static func view(_ pose: Pose, side: CGFloat) -> some View {
        picture(pose, side: side).foregroundStyle(.secondary)
    }

    /// The pose as a SwiftUI Image: a template for the drawn bear, so it
    /// takes the colour around it, and as it is for a picture of your own.
    @MainActor
    static func picture(_ pose: Pose, side: CGFloat, hat: Bool = BearGeometry.wearsHat(), pom: Bool = true) -> Image {
        let image = image(pose, side: side, hat: hat, pom: pom)
        return Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
    }

    static func description(_ pose: Pose) -> String {
        switch pose {
        case .sit: return "The bear, sat waiting"
        case .wave: return "The bear, waving"
        case .sleep: return "The bear, asleep"
        case .cub: return "A bear cub"
        }
    }

    // MARK: Drawing

    /// The waving bear's Santa-hat pom-pom on its own, in the same square, for
    /// InboxZero to swing beside `image(.wave, pom: false)`.
    @MainActor
    static func wavePom(side: CGFloat) -> NSImage {
        let key = "wavePom@\(side)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(BearGeometry.wavePom(small: side < BearGeometry.smallSide), in: rect)
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    /// Draws the pose from BearGeometry, scaled to the rect.
    static func draw(_ pose: Pose, in rect: NSRect, hat: Bool = BearGeometry.wearsHat()) {
        draw(BearGeometry.inks(pose, side: min(rect.width, rect.height), hat: hat), in: rect)
    }

    /// It's in black, as the image is a template and takes its colour from around it.
    static func draw(_ inks: [BearGeometry.Ink], in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let side = min(rect.width, rect.height)
        let scale = side / 24
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(.black)
        context.setStrokeColor(.black)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for ink in inks {
            context.saveGState()
            if let outside = ink.outside {
                context.addRect(CGRect(x: -24, y: -24, width: 72, height: 72))
                context.addPath(outside)
                context.clip(using: .evenOdd)
            }
            context.addPath(ink.path)
            if let width = ink.width {
                context.setLineWidth(width)
                context.strokePath()
            } else {
                context.fillPath()
            }
            context.restoreGState()
        }
        context.restoreGState()
    }
}
