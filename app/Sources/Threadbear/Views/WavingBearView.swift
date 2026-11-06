import AppKit
import QuartzCore

/// The working line's mascot, alive: she pops up when a turn starts, gives a
/// little wave every few seconds, breathes, and blinks now and then. Mike
/// watches this line while a turn runs, so the wave comes in bursts rather
/// than flapping non-stop next to the text he's reading.
///
/// It's the waving pose from Mascot.swift cut into layers, so all of the
/// movement is Core Animation and carries on while the main thread is busy
/// (AGENTS.md, "Animations"). Under Reduce Motion it's the still pose.
final class WavingBearView: NSView {
    /// The line colour. A plain layer can't be a template image, so this
    /// is resolved by hand whenever the appearance changes.
    var tint: NSColor = .secondaryLabelColor {
        didSet { applyTint() }
    }

    /// One full run of each movement. The lengths don't divide evenly into
    /// each other, so the wave, breath and blink never settle into one
    /// obvious repeating loop.
    enum Timing {
        static let wave: CFTimeInterval = 6
        static let breath: CFTimeInterval = 3.4
        static let blink: CFTimeInterval = 7.3
        /// The paw's swing in degrees at seconds into the wave. Starts and
        /// ends at rest, so the still pose and the repeat both line up, and
        /// only ever swings outward: at rest the hand is already by the
        /// hair, so going the other way runs it through the head.
        static let paw: [(at: Double, degrees: Double)] = [
            (0, 0), (0.16, 14), (0.38, 3), (0.6, 14), (0.82, 3), (1.04, 10), (1.3, 0), (wave, 0),
        ]
    }

    /// Holds the grid's y-down coordinates, as the static pose has.
    private let stage = CALayer()
    /// The pop on arrival. A layer of its own so it can't fight the breath.
    private let arrival = CALayer()
    /// Everything that sways and breathes.
    private let figure = CALayer()
    private let ears = CAShapeLayer()
    private let earMask = CAShapeLayer()
    private let head = CAShapeLayer()
    private let eyes = CAShapeLayer()
    /// The parting and the lock on top.
    private let fringe = CAShapeLayer()
    /// The smile, where the bear's nose was.
    private let nose = CAShapeLayer()
    /// The arm and hand, swinging about the shoulder.
    private let paw = CALayer()
    private let arm = CAShapeLayer()
    private let pad = CAShapeLayer()
    /// Your own picture of the mascot (Settings > Appearance), shown in
    /// place of the drawn parts. It breathes and sways as they do, on
    /// tracks of its own: it sits outside `stage`, whose y-down grid
    /// would stand a picture on its head.
    private let portrait = CALayer()
    private var pictures: NSObjectProtocol?

    private var builtSide: CGFloat = 0
    private var builtPictures = -1

    /// Whether any of the looping movement is on.
    var isAnimating: Bool { paw.animation(forKey: Key.paw) != nil }

    private enum Key {
        static let paw = "bear.paw"
        static let sway = "bear.sway"
        static let breath = "bear.breath"
        static let blink = "bear.blink"
        static let arrival = "bear.arrival"
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The paw swings a little past the grid's right edge.
        clipsToBounds = false
        stage.isGeometryFlipped = true
        layer?.addSublayer(stage)
        stage.addSublayer(arrival)
        arrival.addSublayer(figure)
        ears.mask = earMask
        for part in [ears, head, fringe, eyes, nose] { figure.addSublayer(part) }
        figure.addSublayer(paw)
        for part in [arm, pad] { paw.addSublayer(part) }
        layer?.addSublayer(portrait)
        portrait.contentsGravity = .resizeAspect
        pictures = NotificationCenter.default.addObserver(forName: Appearance.picturesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        setAccessibilityRole(.image)
        setAccessibilityLabel(Bear.description(.wave))
        applyTint()
        // init(frame:) doesn't go through setFrameSize.
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let pictures { NotificationCenter.default.removeObserver(pictures) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuild()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyScale()
    }

    // MARK: Moving

    /// Starts the movement, if it isn't going already. `fresh` adds the
    /// pop up from nothing, for a turn that's only just begun.
    func start(fresh: Bool, reduceMotion: Bool? = nil) {
        guard !(reduceMotion ?? Juice.reduceMotion), !isAnimating else { return }
        paw.add(Self.loop("transform.rotation.z", length: Timing.wave,
                          keys: Timing.paw.map { ($0.at, $0.degrees * .pi / 180) }), forKey: Key.paw)
        // The whole bear leans with the wave, a fraction as far.
        figure.add(Self.loop("transform.rotation.z", length: Timing.wave,
                             keys: Timing.paw.map { ($0.at, -$0.degrees * 0.16 * .pi / 180) }), forKey: Key.sway)
        figure.add(Self.loop("transform.scale", length: Timing.breath,
                             keys: [(0, 1), (Timing.breath / 2, 1.03), (Timing.breath, 1)]), forKey: Key.breath)
        // One blink partway through, then a double one before it repeats.
        eyes.add(Self.loop("transform.scale.y", length: Timing.blink, keys: [
            (0, 1), (3, 1), (3.06, 0.12), (3.14, 1),
            (6.7, 1), (6.76, 0.12), (6.84, 1), (6.9, 0.12), (6.98, 1), (Timing.blink, 1),
        ]), forKey: Key.blink)
        portrait.add(Self.loop("transform.rotation.z", length: Timing.wave,
                               keys: Timing.paw.map { ($0.at, $0.degrees * 0.5 * .pi / 180) }), forKey: Key.sway)
        portrait.add(Self.loop("transform.scale", length: Timing.breath,
                               keys: [(0, 1), (Timing.breath / 2, 1.05), (Timing.breath, 1)]), forKey: Key.breath)
        if fresh {
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.4
            pop.toValue = 1
            pop.mass = 0.6
            pop.stiffness = 240
            pop.damping = 11
            pop.duration = pop.settlingDuration
            arrival.add(pop, forKey: Key.arrival)
            portrait.add(pop, forKey: Key.arrival)
        }
    }

    func stop() {
        paw.removeAnimation(forKey: Key.paw)
        figure.removeAnimation(forKey: Key.sway)
        figure.removeAnimation(forKey: Key.breath)
        eyes.removeAnimation(forKey: Key.blink)
        arrival.removeAnimation(forKey: Key.arrival)
        portrait.removeAllAnimations()
    }

    /// A forever-repeating track from (seconds, value) pairs. Thirty frames
    /// a second is plenty at this size, and this runs for whole turns, so
    /// it shouldn't keep the display at 120.
    private static func loop(_ keyPath: String, length: CFTimeInterval, keys: [(Double, Double)]) -> CAKeyframeAnimation {
        let track = CAKeyframeAnimation(keyPath: keyPath)
        track.values = keys.map(\.1)
        track.keyTimes = keys.map { NSNumber(value: $0.0 / length) }
        track.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        track.calculationMode = .cubic
        track.duration = length
        track.repeatCount = .infinity
        // Keeps its place through a layer leaving and rejoining the tree;
        // stop() is what ends it.
        track.isRemovedOnCompletion = false
        track.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        return track
    }

    // MARK: Drawing

    private func applyTint() {
        var ink: CGColor = tint.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { ink = self.tint.cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for line in [ears, head, fringe, nose, arm, pad] {
            line.strokeColor = ink
            line.fillColor = nil
        }
        eyes.fillColor = ink
        eyes.strokeColor = nil
        CATransaction.commit()
    }

    private func applyScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [stage, arrival, figure, paw, ears, earMask, head, fringe, eyes, nose, arm, pad, portrait] {
            part.contentsScale = scale
        }
        CATransaction.commit()
    }

    /// Lays the parts out for this size. Paths are made at the real size,
    /// not scaled afterwards, so the lines stay sharp at any zoom.
    private func rebuild() {
        let side = min(bounds.width, bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stage.frame = bounds
        let version = Appearance.shared.slotsVersion
        guard side > 0, side != builtSide || version != builtPictures else { return }
        builtSide = side
        builtPictures = version
        let unit = side / 24
        let scale = CGAffineTransform(scaleX: unit, y: unit)
        var transform = scale
        let square = CGRect(x: 0, y: 0, width: side, height: side)

        /// Pins a layer so it turns and scales about this spot on the grid.
        func pin(_ part: CALayer, about point: CGPoint) {
            part.bounds = square
            part.anchorPoint = CGPoint(x: point.x / 24, y: point.y / 24)
            part.position = CGPoint(x: point.x * unit, y: point.y * unit)
        }

        // The same shapes as the still pose (Mascot.figure); BearTests
        // checks the still layers against it.
        let pose = Mascot.figure(.wave)
        func scaled(_ path: CGPath?) -> CGPath? {
            guard let path else { return nil }
            return path.copy(using: &transform)
        }

        pin(arrival, about: pose.feet)
        pin(figure, about: pose.feet)
        pin(eyes, about: pose.eyeLine)
        pin(paw, about: Mascot.Wave.shoulder)
        for part in [ears, head, fringe, nose, arm, pad] { part.frame = square }

        // A picture of your own stands in for all the drawn parts.
        let picture = Appearance.shared.mascot(.wave)
        portrait.bounds = square
        portrait.position = CGPoint(x: bounds.midX, y: bounds.midY)
        portrait.contents = picture?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        portrait.isHidden = picture == nil
        for part in [ears, head, fringe, eyes, nose, paw] as [CALayer] { part.isHidden = picture != nil }

        head.path = scaled(pose.head)
        ears.path = scaled(pose.tails)
        // The tails show only outside the head, so the outlines don't cross.
        let outside = CGMutablePath()
        outside.addRect(square.insetBy(dx: -side, dy: -side))
        outside.addPath(pose.head, transform: scale)
        earMask.frame = square
        earMask.path = outside
        earMask.fillRule = .evenOdd
        earMask.fillColor = NSColor.black.cgColor

        fringe.path = scaled(pose.fringe)
        eyes.path = scaled(pose.eyes)
        nose.path = scaled(pose.mouth)
        arm.path = scaled(pose.arm)
        pad.path = scaled(pose.hand)

        for line in [ears, head, fringe, nose, arm, pad] {
            line.lineCap = .round
            line.lineJoin = .round
        }
        for line in [ears, head, arm, pad] { line.lineWidth = Mascot.lineWidth * unit }
        fringe.lineWidth = Mascot.lineWidth * 0.85 * unit
        nose.lineWidth = Mascot.lineWidth * 0.7 * unit
        applyScale()
    }

    /// The layers as they stand, for BearTests to compare with the pose.
    func renderStill(in context: CGContext) {
        layer?.render(in: context)
    }

    #if DEBUG
    /// Draws the mascot as it looks `seconds` into its loops, from the real
    /// tracks, for BearTests' BEAR_FRAMES. Core Animation can't be sampled
    /// to a bitmap, least of all with the screen locked.
    func renderFrame(at seconds: Double, in context: CGContext) {
        let moved: [(CALayer, String)] = [(paw, Key.paw), (figure, Key.sway), (figure, Key.breath), (eyes, Key.blink)]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (part, key) in moved {
            guard let track = part.animation(forKey: key) as? CAKeyframeAnimation,
                  let values = track.values as? [Double], let times = track.keyTimes?.map(\.doubleValue),
                  let keyPath = track.keyPath else { continue }
            let t = seconds.truncatingRemainder(dividingBy: track.duration) / track.duration
            let i = max(0, (times.lastIndex { $0 <= t } ?? 0))
            let j = min(i + 1, values.count - 1)
            let span = max(0.000_001, times[j] - times[i])
            part.setValue(values[i] + (values[j] - values[i]) * min(1, (t - times[i]) / span), forKeyPath: keyPath)
        }
        CATransaction.commit()
        layer?.render(in: context)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [paw, figure, eyes] { part.setAffineTransform(.identity) }
        CATransaction.commit()
    }
    #endif
}
