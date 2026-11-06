import AppKit
import SwiftUI

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
    @MainActor static var workingSide: CGFloat { TypeScale.scaled(Appearance.shared.mascot(.wave) == nil ? 26 : 30) }

    private static var cache: [String: NSImage] = [:]
    /// Which pictures `cache` was made from (Appearance.slotsVersion).
    private static var cachedPictures = 0

    /// The pose as a square template image `side` points across. The
    /// drawing is redone at whatever resolution it's shown at, so the
    /// lines stay crisp on any screen and at any zoom.
    @MainActor
    static func image(_ pose: Pose, side: CGFloat = 24) -> NSImage {
        if cachedPictures != Appearance.shared.slotsVersion {
            cache = [:]
            cachedPictures = Appearance.shared.slotsVersion
        }
        let key = "\(pose.rawValue)@\(side)"
        if let cached = cache[key] { return cached }
        // Your own picture of her, if you've set one (Settings >
        // Appearance): in its own colours, not a template.
        if let picture = Appearance.shared.mascot(pose) {
            let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let scale = min(rect.width / picture.size.width, rect.height / picture.size.height)
                let size = NSSize(width: picture.size.width * scale, height: picture.size.height * scale)
                NSGraphicsContext.current?.imageInterpolation = .high
                picture.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
                return true
            }
            image.accessibilityDescription = description(pose)
            cache[key] = image
            return image
        }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(pose, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(pose)
        cache[key] = image
        return image
    }

    /// The pose for SwiftUI: the drawn mascot takes the text colour, a
    /// picture of your own keeps its colours.
    @MainActor
    static func view(_ pose: Pose, side: CGFloat) -> some View {
        let image = image(pose, side: side)
        return Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .foregroundStyle(.secondary)
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
