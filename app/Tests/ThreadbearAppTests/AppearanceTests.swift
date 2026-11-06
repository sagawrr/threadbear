import AppKit
import XCTest
@testable import Threadbear

/// This fork's look (Appearance.swift): Threadbear as it comes until you
/// change something, each part kept in the app's own defaults, your
/// pictures copied into a folder of its own, and one way back.
@MainActor
final class AppearanceTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    /// Stands in for ~/Library/Application Support/Threadbear/appearance.
    private var folder: URL!
    /// Where the pictures "you" pick come from.
    private var sources: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "AppearanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        folder = root.appendingPathComponent("appearance")
        sources = root.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        super.tearDown()
    }

    private func look() -> Appearance { Appearance(defaults: defaults, folder: folder) }

    private func kept() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: The original

    func testAFreshInstallIsThreadbearAsItComes() {
        Appearance.applyAccentAtLaunch(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "AppleAccentColor"), "the Mac's own accent is left alone")
        let look = look()
        XCTAssertEqual(look.backdrop, .off)
        XCTAssertEqual(look.accent, .system)
        XCTAssertEqual(look.effectivePanelOpacity, 1)
        XCTAssertNil(look.icon)
        for pose in Bear.Pose.allCases { XCTAssertNil(look.mascot(pose), "\(pose) is the bear") }
        for slot in Appearance.Slot.allCases { XCTAssertNil(look.picture(slot)) }
        XCTAssertTrue(look.isOriginal)
    }

    func testPanelsAreSolidWithNothingBehindThem() {
        let look = look()
        look.panelOpacity = 0.5
        XCTAssertEqual(look.effectivePanelOpacity, 1)
        // A picture backdrop with no picture chosen has nothing to show.
        look.backdrop = .picture
        XCTAssertEqual(look.effectivePanelOpacity, 1)
        look.backdrop = .desktop
        XCTAssertEqual(look.effectivePanelOpacity, 0.5)
    }

    func testABackdropStartsOutReadable() {
        let look = look()
        look.backdrop = .desktop
        XCTAssertGreaterThanOrEqual(look.panelOpacity, 0.65)
        XCTAssertGreaterThanOrEqual(look.blur, 12)
        XCTAssertGreaterThanOrEqual(look.dim, 0.2)
    }

    func testWhatIsSetIsRemembered() {
        let look = look()
        look.backdrop = .desktop
        look.blur = 7
        look.dim = 0.5
        look.panelOpacity = 0.5
        look.accent = .mint
        XCTAssertFalse(look.isOriginal)
        let again = self.look()
        XCTAssertEqual(again.backdrop, .desktop)
        XCTAssertEqual(again.blur, 7)
        XCTAssertEqual(again.dim, 0.5)
        XCTAssertEqual(again.panelOpacity, 0.5)
        XCTAssertEqual(again.accent, .mint)
    }

    func testSavedNumbersOutOfRangeArePulledIn() {
        defaults.set(999.0, forKey: Appearance.Key.blur)
        defaults.set(-3.0, forKey: Appearance.Key.dim)
        defaults.set(0.0, forKey: Appearance.Key.panel)
        let look = look()
        XCTAssertEqual(look.blur, Appearance.blurRange.upperBound)
        XCTAssertEqual(look.dim, Appearance.dimRange.lowerBound)
        // Never so see-through that text over a picture can't be read.
        XCTAssertEqual(look.panelOpacity, Appearance.panelRange.lowerBound)
    }

    // MARK: Accent

    /// The accent is macOS's own setting, written to this app's defaults
    /// only; the Mac's own choice takes it away again.
    func testTheAccentIsWrittenWhereAppKitReadsIt() {
        let look = look()
        look.accent = .violet
        XCTAssertEqual(defaults.integer(forKey: "AppleAccentColor"), 5)
        XCTAssertNotNil(defaults.string(forKey: "AppleHighlightColor"))
        defaults.removeObject(forKey: "AppleAccentColor")
        Appearance.applyAccentAtLaunch(defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "AppleAccentColor"), 5, "put back as the app starts")
        look.accent = .system
        XCTAssertNil(defaults.object(forKey: "AppleAccentColor"))
        XCTAssertNil(defaults.object(forKey: "AppleHighlightColor"))
        XCTAssertEqual(look.accentAtLaunch, .system, "what the app opened with doesn't move")
    }

    func testEveryAccentButTheMacsOwnHasItsOwnColour() {
        var seen = Set<Int>()
        for accent in Appearance.Accent.allCases where accent != .system {
            defaults.removeObject(forKey: "AppleAccentColor")
            look().accent = accent
            XCTAssertNotNil(defaults.object(forKey: "AppleAccentColor"), "\(accent)")
            XCTAssertTrue(seen.insert(defaults.integer(forKey: "AppleAccentColor")).inserted, "\(accent) shares a colour")
        }
    }

    // MARK: Pictures

    func testAPictureOfYoursStandsInForTheBearAndItsCub() throws {
        let look = look()
        let bear = try photo("bear.jpg", width: 64)
        look.choosePicture(bear, for: .mascot)
        XCTAssertNil(look.problem)
        XCTAssertEqual(kept().count, 1, "a copy of its own, in its folder")
        XCTAssertEqual(look.mascot(.wave)?.size.width, 64)
        XCTAssertEqual(look.mascot(.sit)?.size.width, 64)
        XCTAssertEqual(look.mascot(.cub)?.size.width, 64, "no cub of its own: the bear's")
        look.choosePicture(try photo("cub.jpg", width: 32), for: .mascotSmall)
        XCTAssertEqual(look.mascot(.cub)?.size.width, 32)
        XCTAssertEqual(look.mascot(.wave)?.size.width, 64)
        XCTAssertFalse(look.isOriginal)
        // Still there the next time the app opens.
        XCTAssertEqual(self.look().mascot(.wave)?.size.width, 64)

        look.removePicture(.mascot)
        XCTAssertNil(look.mascot(.wave), "the bear again")
        XCTAssertEqual(look.mascot(.cub)?.size.width, 32)
        XCTAssertEqual(kept().count, 1, "its copy went with it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bear.path), "the file it was picked from is yours")
    }

    func testReplacingAPictureDropsTheOldCopy() throws {
        let look = look()
        look.choosePicture(try photo("one.jpg", width: 40), for: .librarian)
        look.choosePicture(try photo("two.png", width: 50), for: .scheduled)
        look.choosePicture(try photo("three.jpg", width: 60), for: .scheduled)
        XCTAssertEqual(look.picture(.librarian)?.size.width, 40)
        XCTAssertEqual(look.picture(.scheduled)?.size.width, 60)
        XCTAssertEqual(kept().count, 2)
    }

    func testAPictureSetByHandOutsideTheFolderIsNeverDeleted() throws {
        let own = try photo("mine.jpg", width: 48)
        defaults.set(own.path, forKey: "appearance.picture.mascot")
        let look = look()
        XCTAssertEqual(look.mascot(.wave)?.size.width, 48)
        look.removePicture(.mascot)
        XCTAssertNil(look.mascot(.wave))
        XCTAssertTrue(FileManager.default.fileExists(atPath: own.path))
    }

    func testAPhotoIsToldFromACutOut() throws {
        let plain = try XCTUnwrap(Appearance.readScaled(try photo("photo.jpg", width: 80), maxPixels: 80))
        XCTAssertFalse(Appearance.isCutOut(plain))
        let cut = try XCTUnwrap(Appearance.readScaled(try cutOut("cut.png", width: 80), maxPixels: 80))
        XCTAssertTrue(Appearance.isCutOut(cut))
        // Either way the bear's place takes it, at the size asked for.
        XCTAssertEqual(Bear.portrait(plain, side: 30).size, NSSize(width: 30, height: 30))
        XCTAssertEqual(Bear.portrait(cut, side: 30).size, NSSize(width: 30, height: 30))
    }

    // MARK: Icon

    func testAPhotoBecomesAnIconTile() throws {
        let look = look()
        look.chooseIcon(try photo("wide.jpg", width: 400, height: 200))
        XCTAssertNil(look.problem)
        XCTAssertNotNil(look.icon)
        XCTAssertEqual(kept(), [Appearance.iconName], "the name app/build-app.sh looks for")
        let saved = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: folder.appendingPathComponent(Appearance.iconName))))
        XCTAssertEqual(saved.pixelsWide, 1024)
        XCTAssertEqual(saved.pixelsHigh, 1024)
        XCTAssertEqual(saved.colorAt(x: 4, y: 4)?.alphaComponent, 0, "margins round the tile")
        XCTAssertEqual(saved.colorAt(x: 512, y: 512)?.alphaComponent, 1)
        XCTAssertNotNil(self.look().icon, "still there the next time the app opens")

        look.removeIcon()
        XCTAssertNil(look.icon)
        XCTAssertEqual(kept(), [])
    }

    func testAnIconThatIsAlreadyOneIsOnlyFittedIn() throws {
        let icon = try XCTUnwrap(Appearance.readScaled(try cutOut("icon.png", width: 512), maxPixels: 512))
        let tile = try XCTUnwrap(Appearance.iconTile(icon))
        XCTAssertEqual(tile.width, 1024)
        XCTAssertEqual(tile.height, 1024)
        // Not cropped into a tile of its own: its own edge reaches the canvas's.
        let rep = NSBitmapImageRep(cgImage: tile)
        XCTAssertEqual(rep.colorAt(x: 10, y: 512)?.alphaComponent, 1)
    }

    // MARK: The way back

    func testRestoringTheOriginalPutsEverythingBack() throws {
        let look = look()
        let wall = try photo("wall.jpg", width: 300, height: 200)
        look.chooseWallpaper(wall)
        XCTAssertEqual(look.backdrop, .picture, "choosing one shows it")
        look.choosePicture(try photo("bear.jpg", width: 64), for: .mascot)
        look.choosePicture(try photo("page.jpg", width: 64), for: .librarian)
        look.chooseIcon(try photo("icon.jpg", width: 128))
        look.accent = .sky
        look.blur = 3
        look.dim = 0.1
        look.panelOpacity = 0.5
        XCTAssertEqual(kept().count, 4)
        XCTAssertFalse(look.isOriginal)

        look.restoreOriginal()
        XCTAssertTrue(look.isOriginal)
        XCTAssertEqual(look.backdrop, .off)
        XCTAssertEqual(look.accent, .system)
        XCTAssertNil(look.wallpaperPath)
        XCTAssertNil(look.icon)
        XCTAssertNil(look.mascot(.wave))
        XCTAssertEqual(look.effectivePanelOpacity, 1)
        XCTAssertEqual(kept(), [], "its copies are gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wall.path), "the files they came from are yours")
        XCTAssertNil(defaults.object(forKey: "AppleAccentColor"))
        let keys = defaults.persistentDomain(forName: suite)?.keys.filter { $0.hasPrefix("appearance.") } ?? []
        XCTAssertEqual(Array(keys), [], "nothing of this fork's left in the defaults")
        XCTAssertTrue(self.look().isOriginal, "and it stays that way")
    }

    func testTakingTheWallpaperAwayGoesBackToThePlainWindow() throws {
        let look = look()
        look.chooseWallpaper(try photo("wall.jpg", width: 300, height: 200))
        look.removeWallpaper()
        XCTAssertEqual(look.backdrop, .off)
        XCTAssertEqual(kept(), [])
    }

    func testABlurKeepsThePicturesShape() throws {
        let picture = try XCTUnwrap(Self.picture(width: 400, height: 200, alpha: false))
        let sharp = try XCTUnwrap(Appearance.blurred(picture, points: 0))
        XCTAssertEqual(sharp.width, 400)
        let soft = try XCTUnwrap(Appearance.blurred(picture, points: 20))
        XCTAssertEqual(soft.width, 400)
        XCTAssertEqual(soft.height, 200)
        // A big picture is blurred at a smaller size, in the same shape.
        let big = try XCTUnwrap(Self.picture(width: 4000, height: 2000, alpha: false))
        let small = try XCTUnwrap(Appearance.blurred(big, points: 20))
        XCTAssertEqual(small.width, 1600)
        XCTAssertEqual(small.height, 800)
    }

    func testAFileThatIsNotAPictureIsRefused() throws {
        let look = look()
        let file = sources.appendingPathComponent("notes.txt")
        try Data("not a picture".utf8).write(to: file)
        look.chooseWallpaper(file)
        XCTAssertNil(look.wallpaperPath)
        XCTAssertNotNil(look.problem)
        XCTAssertEqual(look.backdrop, .off, "the backdrop stays as it was")
        look.choosePicture(file, for: .mascot)
        XCTAssertNil(look.mascot(.wave))
        look.chooseIcon(file)
        XCTAssertNil(look.icon)
        XCTAssertEqual(kept(), [])
        XCTAssertTrue(look.isOriginal)
    }

    // MARK: Pictures to pick

    /// A plain photo: no see-through parts.
    private func photo(_ name: String, width: Int, height: Int? = nil) throws -> URL {
        let image = try XCTUnwrap(Self.picture(width: width, height: height ?? width, alpha: false))
        let type: NSBitmapImageRep.FileType = name.hasSuffix(".png") ? .png : .jpeg
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: type, properties: [:]))
        let url = sources.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// A PNG with an alpha channel, as a character cut out of its
    /// background or a ready-made icon has.
    private func cutOut(_ name: String, width: Int) throws -> URL {
        let image = try XCTUnwrap(Self.picture(width: width, height: width, alpha: true))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let url = sources.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private static func picture(width: Int, height: Int, alpha: Bool) -> CGImage? {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue)
        context?.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.7, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
