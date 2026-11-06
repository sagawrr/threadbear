import AppKit
import CoreImage
import ImageIO
import Observation
import SwiftUI

/// How the window looks, in this fork. Out of the box it's Threadbear as
/// it comes: the plain window, the Mac's own accent, the bear. Settings >
/// Appearance can change each part on its own: what's behind the panels
/// (the desktop blurred, or a picture of yours), how much of it shows
/// through them, the accent colour, and a picture of yours in place of
/// the bear, the two page pictures and the app's icon. "Restore the
/// Original Look" there puts it all back.
///
/// All of it is this Mac's own (UserDefaults), and none of it goes to the
/// runner or the backend. A picture is yours: Settings copies the file you
/// pick into `Appearance.folder`, outside the repo, so it's never
/// committed or pushed with the code.
@Observable @MainActor
final class Appearance {
    static let shared = Appearance(showsInDock: true)

    /// What's drawn behind the panels.
    enum Backdrop: String, CaseIterable, Identifiable {
        /// The plain window, as upstream has it.
        case off
        /// The desktop and windows behind, blurred (acrylic).
        case desktop
        /// A picture you chose.
        case picture

        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Original"
            case .desktop: "Desktop blur"
            case .picture: "Picture"
            }
        }
    }

    /// The accent colour. macOS only lets an app use its own eight, so
    /// each of these is one of them under another name.
    enum Accent: String, CaseIterable, Identifiable {
        case system, sakura, violet, sky, mint, gold, sunset, ruby, graphite

        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "Mac's own"
            case .sakura: "Sakura"
            case .violet: "Violet"
            case .sky: "Sky"
            case .mint: "Mint"
            case .gold: "Gold"
            case .sunset: "Sunset"
            case .ruby: "Ruby"
            case .graphite: "Graphite"
            }
        }

        /// The swatch in Settings.
        var swatch: Color {
            switch self {
            case .system: Color(nsColor: .controlAccentColor)
            case .sakura: Color(nsColor: .systemPink)
            case .violet: Color(nsColor: .systemPurple)
            case .sky: Color(nsColor: .systemBlue)
            case .mint: Color(nsColor: .systemGreen)
            case .gold: Color(nsColor: .systemYellow)
            case .sunset: Color(nsColor: .systemOrange)
            case .ruby: Color(nsColor: .systemRed)
            case .graphite: Color(nsColor: .systemGray)
            }
        }

        /// What System Settings writes for this colour: `AppleAccentColor`
        /// and `AppleHighlightColor`. In the app's own defaults they
        /// apply to this app alone.
        fileprivate var system: (accent: Int, highlight: String)? {
            switch self {
            case .system: nil
            case .ruby: (0, "1.000000 0.733333 0.721569 Red")
            case .sunset: (1, "1.000000 0.874510 0.701961 Orange")
            case .gold: (2, "1.000000 0.937255 0.690196 Yellow")
            case .mint: (3, "0.752941 0.964706 0.678431 Green")
            case .sky: (4, "0.698039 0.843137 1.000000 Blue")
            case .violet: (5, "0.968627 0.831373 1.000000 Purple")
            case .sakura: (6, "1.000000 0.749020 0.823529 Pink")
            case .graphite: (-1, "0.847059 0.847059 0.862745 Graphite")
            }
        }
    }

    /// The pictures you can put in place of Threadbear's own: the bear
    /// (the working line, the tour), the cub that stands in while
    /// sub-agents are out, and the two at the top of the Librarian's and
    /// Scheduled's pages.
    enum Slot: String, CaseIterable, Identifiable {
        case mascot, mascotSmall, librarian, scheduled

        var id: String { rawValue }
        var title: String {
            switch self {
            case .mascot: "Bear"
            case .mascotSmall: "Cub"
            case .librarian: "Librarian page"
            case .scheduled: "Scheduled page"
            }
        }
        /// Where it shows, for Settings.
        var detail: String {
            switch self {
            case .mascot: "Beside \u{201C}Bear with me\u{201D} while a thread works, and in the tour"
            case .mascotSmall: "While sub-agents are out. Without one, the bear's picture"
            case .librarian: "At the top of the Librarian's page"
            case .scheduled: "At the top of Scheduled's page"
            }
        }
        fileprivate var key: String { "appearance.picture.\(rawValue)" }
    }

    enum Key {
        static let backdrop = "appearance.backdrop"
        static let wallpaper = "appearance.wallpaperPath"
        static let blur = "appearance.blur"
        static let dim = "appearance.dim"
        static let panel = "appearance.panelOpacity"
        static let accent = "appearance.accent"
    }

    /// Threadbear as it comes.
    nonisolated static let defaultBackdrop = Backdrop.off
    nonisolated static let defaultAccent = Accent.system
    nonisolated static let blurRange: ClosedRange<Double> = 0...40
    nonisolated static let dimRange: ClosedRange<Double> = 0...0.8
    /// Below about two fifths, text over a busy picture stops being readable.
    nonisolated static let panelRange: ClosedRange<Double> = 0.4...1
    /// Where the sliders start once there's a backdrop: soft and solid
    /// enough that text over a busy picture reads without squinting, and
    /// not so solid that a dark window hides the picture altogether.
    nonisolated static let defaultBlur = 16.0
    nonisolated static let defaultDim = 0.25
    nonisolated static let defaultPanel = 0.7
    /// The longest side a wallpaper is kept at: enough for a 5K screen's
    /// window, and a fraction of what a camera's picture would take.
    nonisolated static let maxPixels = 3200

    /// Where the pictures you pick are copied: beside the runner's data,
    /// and never in the repo.
    nonisolated static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Threadbear/appearance", isDirectory: true)
    }

    private let defaults: UserDefaults
    /// Where this one keeps its pictures: `Appearance.folder`, but for tests.
    let folder: URL
    /// Whether an icon of yours goes on the Dock: the app's own, not a test's.
    private let showsInDock: Bool

    var backdrop: Backdrop { didSet { defaults.set(backdrop.rawValue, forKey: Key.backdrop) } }
    /// The blur over the picture, in points.
    var blur: Double {
        didSet {
            defaults.set(blur, forKey: Key.blur)
            renderBackdrop()
        }
    }
    /// How far the picture is faded towards the window's own colour.
    var dim: Double { didSet { defaults.set(dim, forKey: Key.dim) } }
    /// How solid the panels are over the backdrop: 1 hides it.
    var panelOpacity: Double { didSet { defaults.set(panelOpacity, forKey: Key.panel) } }
    /// Takes effect when the app next opens (`applyAccentAtLaunch`).
    var accent: Accent {
        didSet {
            defaults.set(accent.rawValue, forKey: Key.accent)
            Self.writeAccent(accent, to: defaults)
        }
    }
    /// The accent the app opened with, so Settings can say when a restart
    /// is needed to see the one picked since.
    let accentAtLaunch: Accent

    private(set) var wallpaperPath: String?
    /// The wallpaper, scaled down. Nil until it's read, or when there's
    /// none (or it can't be read).
    private(set) var wallpaper: NSImage?
    /// The wallpaper as the window draws it: blurred already, so showing
    /// it costs no more than any picture.
    private(set) var backdropImage: NSImage?
    @ObservationIgnored private var wallpaperPixels: CGImage?
    /// Counts the blurs asked for, so a slow one that finishes after a
    /// newer one is dropped.
    @ObservationIgnored private var renders = 0
    /// Why the last picture wasn't taken, for Settings to say.
    private(set) var problem: String?
    /// Bumped when one of the pictures changes, so what shows it redraws.
    private(set) var slotsVersion = 0 {
        didSet { NotificationCenter.default.post(name: Self.picturesChanged, object: self) }
    }
    /// Posted when a mascot or page picture changes, for the AppKit side
    /// (the transcript's working line) to draw the new one.
    nonisolated static let picturesChanged = Notification.Name("Appearance.picturesChanged")
    /// Page pictures already read, by path: a page asks every time it draws.
    @ObservationIgnored private var slotCache: [String: NSImage] = [:]

    init(defaults: UserDefaults = .standard, folder: URL = Appearance.folder, showsInDock: Bool = false) {
        self.defaults = defaults
        self.folder = folder
        self.showsInDock = showsInDock
        backdrop = defaults.string(forKey: Key.backdrop).flatMap(Backdrop.init(rawValue:)) ?? Self.defaultBackdrop
        blur = Self.number(defaults, Key.blur, in: Self.blurRange, default: Self.defaultBlur)
        dim = Self.number(defaults, Key.dim, in: Self.dimRange, default: Self.defaultDim)
        panelOpacity = Self.number(defaults, Key.panel, in: Self.panelRange, default: Self.defaultPanel)
        let accent = Self.savedAccent(defaults)
        self.accent = accent
        accentAtLaunch = accent
        wallpaperPath = defaults.string(forKey: Key.wallpaper)
        icon = Self.readScaled(folder.appendingPathComponent(Self.iconName), maxPixels: 256)
        loadWallpaper()
    }

    /// Whether anything at all has been changed from Threadbear as it comes.
    var isOriginal: Bool {
        _ = slotsVersion
        return backdrop == .off && accent == .system && wallpaperPath == nil && icon == nil
            && Slot.allCases.allSatisfy { defaults.string(forKey: $0.key) == nil }
            && [Key.blur, Key.dim, Key.panel].allSatisfy { defaults.object(forKey: $0) == nil }
    }

    /// Threadbear as it comes: no backdrop, the Mac's accent, the bear, its
    /// own page pictures and icon. Deletes this app's copies of your
    /// pictures (never the files you picked them from).
    func restoreOriginal() {
        removeWallpaper()
        for slot in Slot.allCases { removePicture(slot) }
        removeIcon()
        backdrop = .off
        accent = .system
        blur = Self.defaultBlur
        dim = Self.defaultDim
        panelOpacity = Self.defaultPanel
        for key in [Key.backdrop, Key.accent, Key.blur, Key.dim, Key.panel] { defaults.removeObject(forKey: key) }
        problem = nil
    }

    private static func number(_ defaults: UserDefaults, _ key: String, in range: ClosedRange<Double>, default value: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return value }
        return min(max(defaults.double(forKey: key), range.lowerBound), range.upperBound)
    }

    nonisolated private static func savedAccent(_ defaults: UserDefaults) -> Accent {
        defaults.string(forKey: Key.accent).flatMap(Accent.init(rawValue:)) ?? defaultAccent
    }

    /// What the panels are drawn at: solid unless there's a backdrop to see.
    var effectivePanelOpacity: Double {
        switch backdrop {
        case .off: 1
        case .desktop: panelOpacity
        case .picture: backdropImage == nil ? 1 : panelOpacity
        }
    }

    // MARK: Accent

    /// Before the app's first window: AppKit reads the accent once, as it
    /// starts. Called from ThreadbearApp.init.
    nonisolated static func applyAccentAtLaunch(defaults: UserDefaults = .standard) {
        writeAccent(savedAccent(defaults), to: defaults)
    }

    nonisolated private static func writeAccent(_ accent: Accent, to defaults: UserDefaults) {
        if let system = accent.system {
            defaults.set(system.accent, forKey: "AppleAccentColor")
            defaults.set(system.highlight, forKey: "AppleHighlightColor")
        } else {
            defaults.removeObject(forKey: "AppleAccentColor")
            defaults.removeObject(forKey: "AppleHighlightColor")
        }
    }

    // MARK: Wallpaper

    /// Copies the picture into `folder` and shows it. The copy is what's
    /// kept, so moving or deleting the original changes nothing.
    func chooseWallpaper(_ source: URL) {
        guard let copy = importPicture(source, named: "wallpaper") else { return }
        let old = wallpaperPath
        wallpaperPath = copy.path
        defaults.set(copy.path, forKey: Key.wallpaper)
        if let old, old != copy.path { removeIfOurs(old) }
        backdrop = .picture
        loadWallpaper()
    }

    func removeWallpaper() {
        if let old = wallpaperPath { removeIfOurs(old) }
        wallpaperPath = nil
        setWallpaper(nil)
        defaults.removeObject(forKey: Key.wallpaper)
        if backdrop == .picture { backdrop = .off }
    }

    /// Reads the picture off the main thread: a big one takes a moment to
    /// decode, and the window shouldn't wait for it.
    private func loadWallpaper() {
        guard let path = wallpaperPath else {
            setWallpaper(nil)
            return
        }
        Task.detached(priority: .userInitiated) {
            let image = Self.readScaled(URL(fileURLWithPath: path), maxPixels: Self.maxPixels)
            await MainActor.run {
                guard self.wallpaperPath == path else { return }
                self.setWallpaper(image)
                self.problem = image == nil ? "That picture couldn't be read." : nil
            }
        }
    }

    private func setWallpaper(_ image: NSImage?) {
        wallpaper = image
        wallpaperPixels = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if image == nil { backdropImage = nil }
        renderBackdrop()
    }

    /// Blurs the wallpaper for the window, off the main thread: dragging
    /// the slider asks for this many times a second.
    private func renderBackdrop() {
        renders += 1
        guard let pixels = wallpaperPixels else { return }
        let render = renders, points = blur
        Task.detached(priority: .userInitiated) {
            let blurred = Self.blurred(pixels, points: points)
            await MainActor.run {
                guard render == self.renders, let blurred else { return }
                self.backdropImage = NSImage(cgImage: blurred, size: NSSize(width: blurred.width, height: blurred.height))
            }
        }
    }

    nonisolated private static let blurContext = CIContext(options: [.cacheIntermediates: false])

    /// The picture with a blur of `points`, as it would look filling a
    /// window some 1400 points wide. A blurred picture has no fine detail
    /// left, so it's made at a smaller size, which is also much quicker.
    nonisolated static func blurred(_ image: CGImage, points: Double) -> CGImage? {
        guard points >= 0.5 else { return image }
        let full = CIImage(cgImage: image)
        let scale = min(1, 1600 / max(full.extent.width, full.extent.height))
        let small = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let sigma = points * Double(max(small.extent.width, small.extent.height)) / 1400
        // Clamped first, so the edges blur into themselves, not into nothing.
        let soft = small.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: small.extent)
        return blurContext.createCGImage(soft, from: small.extent)
    }

    /// The picture at no more than `maxPixels` on its longer side, turned
    /// the way its EXIF says.
    nonisolated static func readScaled(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: Pictures

    /// Your picture for a slot, if you've set one.
    func picture(_ slot: Slot) -> NSImage? {
        _ = slotsVersion
        guard let path = defaults.string(forKey: slot.key) else { return nil }
        if let cached = slotCache[path] { return cached }
        guard let image = Self.readScaled(URL(fileURLWithPath: path), maxPixels: 1200) else { return nil }
        slotCache[path] = image
        return image
    }

    /// Your picture for a pose of the bear: the cub's own, else the bear's.
    func mascot(_ pose: Bear.Pose) -> NSImage? {
        switch pose {
        case .sit, .wave, .sleep: picture(.mascot)
        case .cub: picture(.mascotSmall) ?? picture(.mascot)
        }
    }

    /// Whether a picture has see-through parts: a character cut out of its
    /// background, or an icon. Those are shown whole; a plain photo is
    /// cropped to a circle (the bear) or a tile (the icon).
    nonisolated static func isCutOut(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    func hasPicture(_ slot: Slot) -> Bool {
        _ = slotsVersion
        return defaults.string(forKey: slot.key) != nil
    }

    func choosePicture(_ source: URL, for slot: Slot) {
        guard let copy = importPicture(source, named: slot.rawValue) else { return }
        let old = defaults.string(forKey: slot.key)
        defaults.set(copy.path, forKey: slot.key)
        if let old, old != copy.path {
            removeIfOurs(old)
            slotCache[old] = nil
        }
        slotsVersion += 1
    }

    func removePicture(_ slot: Slot) {
        if let old = defaults.string(forKey: slot.key) {
            removeIfOurs(old)
            slotCache[old] = nil
        }
        defaults.removeObject(forKey: slot.key)
        slotsVersion += 1
    }

    // MARK: Icon

    /// The icon's file in `folder`. app/build-app.sh looks for this name
    /// too, and builds it into the app in place of the one that ships.
    nonisolated static let iconName = "icon.png"
    /// Your icon, if you've set one.
    private(set) var icon: NSImage?

    /// Makes an icon of the picture and keeps it in `folder`. The Dock
    /// shows it straight away; the app's own file (Finder, Launchpad)
    /// takes it up when the app is next built, which its updates do.
    func chooseIcon(_ source: URL) {
        guard let picture = Self.readScaled(source, maxPixels: 2048),
              let tile = Self.iconTile(picture),
              let png = NSBitmapImageRep(cgImage: tile).representation(using: .png, properties: [:]) else {
            problem = "\(source.lastPathComponent) isn't a picture Threadbear can read."
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent(Self.iconName), options: .atomic)
        } catch {
            problem = "Couldn't save that icon: \(error.localizedDescription)"
            return
        }
        problem = nil
        icon = NSImage(cgImage: tile, size: NSSize(width: 256, height: 256))
        applyIcon()
    }

    func removeIcon() {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.iconName))
        icon = nil
        applyIcon()
    }

    /// Puts your icon on the Dock, or the app's own back. Called once the
    /// app has launched (AppDelegate) and whenever the icon changes.
    func applyIcon() {
        guard showsInDock, let app = NSApp else { return }
        if let icon {
            app.applicationIconImage = icon
        } else if app.applicationIconImage != nil {
            // Nil hands the Dock back the app's own icon.
            app.applicationIconImage = nil
        }
    }

    /// A 1024 by 1024 icon from a picture. A plain photo is cropped to its
    /// middle square and set in the usual rounded tile with its margins; a
    /// picture with see-through parts is taken to be an icon already and
    /// only fitted in.
    nonisolated static func iconTile(_ picture: NSImage) -> CGImage? {
        guard let source = picture.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let width = CGFloat(source.width), height = CGFloat(source.height)
        if isCutOut(picture) {
            let scale = min(1024 / width, 1024 / height)
            let size = CGSize(width: width * scale, height: height * scale)
            context.draw(source, in: CGRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2, width: size.width, height: size.height))
            return context.makeImage()
        }
        let side = min(width, height)
        guard let square = source.cropping(to: CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side).integral) else { return nil }
        // The system's tile: 824 of 1024, corners about 22% of its side.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824), radius = 824 * 0.2237
        context.saveGState()
        context.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(square, in: tile)
        context.restoreGState()
        return context.makeImage()
    }

    // MARK: Files

    /// A copy of `source` in `folder`, under a name of its own each time
    /// so a view holding the old picture never sees it change underneath.
    /// Nil, with `problem` set, when it isn't a picture or can't be copied.
    private func importPicture(_ source: URL, named name: String) -> URL? {
        guard Self.readScaled(source, maxPixels: 64) != nil else {
            problem = "\(source.lastPathComponent) isn't a picture Threadbear can read."
            return nil
        }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let copy = folder.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).\(ext)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
            try FileManager.default.copyItem(at: source, to: copy)
        } catch {
            problem = "Couldn't copy that picture: \(error.localizedDescription)"
            return nil
        }
        problem = nil
        return copy
    }

    /// Deletes a picture this class copied in. Anything outside `folder`
    /// (a path set by hand in the defaults) is somebody's own file.
    private func removeIfOurs(_ path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent().path == folder.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// What's behind the panels (RootView puts it under the dock).
struct AppBackdrop: View {
    @State private var appearance = Appearance.shared

    var body: some View {
        switch appearance.backdrop {
        case .off:
            Color.clear
        case .desktop:
            BehindWindowBlur()
                .ignoresSafeArea()
        case .picture:
            if let picture = appearance.backdropImage {
                GeometryReader { proxy in
                    Image(nsImage: picture)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(Color(nsColor: .windowBackgroundColor).opacity(appearance.dim))
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
    }
}

/// The desktop and the windows behind this one, blurred: macOS's own
/// material, which follows light and dark.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .sidebar
        // Stays see-through while another app is in front; the default
        // goes flat grey then.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The panels' own see-through fill, for the strips beside the dock (the
/// activity bar and the rail), which sit straight on the backdrop.
struct PanelTint: View {
    @State private var appearance = Appearance.shared

    var body: some View {
        let opacity = appearance.effectivePanelOpacity
        Color(nsColor: .windowBackgroundColor)
            .opacity(opacity < 1 ? opacity : 0)
            .ignoresSafeArea()
    }
}
