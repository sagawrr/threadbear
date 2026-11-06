import AppKit
import CoreImage
import ImageIO
import Observation
import SwiftUI

/// How the window looks, in this fork: what's behind the panels (nothing,
/// the desktop blurred, or a picture of your own), how much of it shows
/// through them, and the accent colour. All of it is this Mac's own
/// (UserDefaults), set in Settings > Appearance, and none of it goes to
/// the runner or the backend.
///
/// The picture is yours: Settings copies the file you pick into
/// `Appearance.folder`, outside the repo, so a character you like is never
/// committed or pushed with the code.
@Observable @MainActor
final class Appearance {
    static let shared = Appearance()

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
            case .off: "None"
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

    /// The pictures you can put in place of the drawn mascot: the mascot
    /// herself (the working line, the tour), how she looks hibernating
    /// and while sub-agents are out, and the two at the top of the
    /// Librarian's and Scheduled's pages.
    enum Slot: String, CaseIterable, Identifiable {
        case mascot, mascotAsleep, mascotSmall, librarian, scheduled

        var id: String { rawValue }
        var title: String {
            switch self {
            case .mascot: "Mascot"
            case .mascotAsleep: "Mascot, hibernating"
            case .mascotSmall: "Mascot, sub-agents"
            case .librarian: "Librarian page"
            case .scheduled: "Scheduled page"
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

    nonisolated static let defaultBackdrop = Backdrop.desktop
    nonisolated static let defaultAccent = Accent.sakura
    nonisolated static let blurRange: ClosedRange<Double> = 0...40
    nonisolated static let dimRange: ClosedRange<Double> = 0...0.8
    /// Below about a third, text over a busy picture stops being readable.
    nonisolated static let panelRange: ClosedRange<Double> = 0.35...1
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
    /// Bumped when a page picture changes, so the pages draw the new one.
    private(set) var slotsVersion = 0 {
        didSet { NotificationCenter.default.post(name: Self.picturesChanged, object: self) }
    }
    /// Posted when a mascot or page picture changes, for the AppKit side
    /// (the transcript's working line) to draw the new one.
    nonisolated static let picturesChanged = Notification.Name("Appearance.picturesChanged")
    /// Page pictures already read, by path: a page asks every time it draws.
    @ObservationIgnored private var slotCache: [String: NSImage] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backdrop = defaults.string(forKey: Key.backdrop).flatMap(Backdrop.init(rawValue:)) ?? Self.defaultBackdrop
        blur = Self.number(defaults, Key.blur, in: Self.blurRange, default: 18)
        dim = Self.number(defaults, Key.dim, in: Self.dimRange, default: 0.25)
        panelOpacity = Self.number(defaults, Key.panel, in: Self.panelRange, default: 0.72)
        let accent = Self.savedAccent(defaults)
        self.accent = accent
        accentAtLaunch = accent
        wallpaperPath = defaults.string(forKey: Key.wallpaper)
        loadWallpaper()
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
        if backdrop == .picture { backdrop = .desktop }
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

    // MARK: Page pictures

    /// Your picture for a page, if you've set one.
    func picture(_ slot: Slot) -> NSImage? {
        _ = slotsVersion
        guard let path = defaults.string(forKey: slot.key) else { return nil }
        if let cached = slotCache[path] { return cached }
        guard let image = Self.readScaled(URL(fileURLWithPath: path), maxPixels: 1200) else { return nil }
        slotCache[path] = image
        return image
    }

    /// Your picture for a pose of the mascot: its own, else the mascot's.
    func mascot(_ pose: Bear.Pose) -> NSImage? {
        switch pose {
        case .sit, .wave: picture(.mascot)
        case .sleep: picture(.mascotAsleep) ?? picture(.mascot)
        case .cub: picture(.mascotSmall) ?? picture(.mascot)
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
        let copy = Self.folder.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).\(ext)")
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
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
        guard url.deletingLastPathComponent().path == Self.folder.standardizedFileURL.path else { return }
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
