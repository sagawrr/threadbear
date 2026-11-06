import AppKit

/// The mascot, drawn as line glyphs in code so it reads at 16 pt and can be
/// drawn at any size. The images are templates, so they take the text
/// colour around them like an SF Symbol. One mascot for the app, not one
/// per thread.
///
/// Upstream's is a bear, which is where the names here come from; this
/// fork draws a chibi girl with twin tails instead (Mascot.swift has her
/// shapes). The type keeps its name so upstream's changes still merge.
enum Bear {
    enum Pose: String, CaseIterable {
        /// Sat, looking at you: the background line while jobs run.
        case sit
        /// A hand up: the working line.
        case wave
        /// Eyes shut, a couple of Zs: Hibernating.
        case sleep
        /// A smaller one: sub-agents out in the background.
        case cub
    }

    /// The working line's mascot, in points. A touch bigger than a 16 pt tool
    /// icon so it reads as a character, not a glyph.
    static var workingSide: CGFloat { TypeScale.scaled(26) }

    private static var cache: [String: NSImage] = [:]

    /// The pose as a square template image `side` points across. The
    /// drawing is redone at whatever resolution it's shown at, so the
    /// lines stay crisp on any screen and at any zoom.
    @MainActor
    static func image(_ pose: Pose, side: CGFloat = 24) -> NSImage {
        let key = "\(pose.rawValue)@\(side)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(pose, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(pose)
        cache[key] = image
        return image
    }

    static func description(_ pose: Pose) -> String {
        switch pose {
        case .sit: return "The mascot, sat waiting"
        case .wave: return "The mascot, waving"
        case .sleep: return "The mascot, asleep"
        case .cub: return "A little mascot"
        }
    }

    // MARK: Drawing

    /// Every pose is laid out on a 24 by 24 grid (y down) and scaled to
    /// the rect (Mascot.swift has the shapes).
    static func draw(_ pose: Pose, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(rect.width, rect.height) / 24
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        Mascot.draw(Mascot.figure(pose), in: context)
        context.restoreGState()
    }
}
