import AppKit
import XCTest
@testable import Threadbear

/// This fork's look (Appearance.swift): the backdrop, how see-through the
/// panels are and the accent, all kept in the app's own defaults.
@MainActor
final class AppearanceTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "AppearanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAFreshInstallIsAcrylicAndSakura() {
        let look = Appearance(defaults: defaults)
        XCTAssertEqual(look.backdrop, .desktop)
        XCTAssertEqual(look.accent, .sakura)
        XCTAssertEqual(look.effectivePanelOpacity, look.panelOpacity)
        XCTAssertLessThan(look.panelOpacity, 1)
    }

    func testPanelsAreSolidWithNothingBehindThem() {
        let look = Appearance(defaults: defaults)
        look.backdrop = .off
        XCTAssertEqual(look.effectivePanelOpacity, 1)
        // A picture backdrop with no picture chosen has nothing to show.
        look.backdrop = .picture
        XCTAssertEqual(look.effectivePanelOpacity, 1)
    }

    func testWhatIsSetIsRemembered() {
        let look = Appearance(defaults: defaults)
        look.backdrop = .off
        look.blur = 7
        look.dim = 0.5
        look.panelOpacity = 0.5
        look.accent = .mint
        let again = Appearance(defaults: defaults)
        XCTAssertEqual(again.backdrop, .off)
        XCTAssertEqual(again.blur, 7)
        XCTAssertEqual(again.dim, 0.5)
        XCTAssertEqual(again.panelOpacity, 0.5)
        XCTAssertEqual(again.accent, .mint)
    }

    func testSavedNumbersOutOfRangeArePulledIn() {
        defaults.set(999.0, forKey: Appearance.Key.blur)
        defaults.set(-3.0, forKey: Appearance.Key.dim)
        defaults.set(0.0, forKey: Appearance.Key.panel)
        let look = Appearance(defaults: defaults)
        XCTAssertEqual(look.blur, Appearance.blurRange.upperBound)
        XCTAssertEqual(look.dim, Appearance.dimRange.lowerBound)
        // Never so see-through that text over a picture can't be read.
        XCTAssertEqual(look.panelOpacity, Appearance.panelRange.lowerBound)
    }

    /// The accent is macOS's own setting, written to this app's defaults
    /// only; the Mac's own choice takes it away again.
    func testTheAccentIsWrittenWhereAppKitReadsIt() {
        Appearance.applyAccentAtLaunch(defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "AppleAccentColor"), 6, "sakura is pink, the default")
        XCTAssertNotNil(defaults.string(forKey: "AppleHighlightColor"))
        let look = Appearance(defaults: defaults)
        look.accent = .violet
        XCTAssertEqual(defaults.integer(forKey: "AppleAccentColor"), 5)
        look.accent = .system
        XCTAssertNil(defaults.object(forKey: "AppleAccentColor"))
        XCTAssertNil(defaults.object(forKey: "AppleHighlightColor"))
        XCTAssertEqual(look.accentAtLaunch, .sakura, "what the app opened with doesn't move")
    }

    func testEveryAccentButTheMacsOwnHasItsOwnColour() {
        var seen = Set<Int>()
        for accent in Appearance.Accent.allCases where accent != .system {
            defaults.removeObject(forKey: "AppleAccentColor")
            Appearance(defaults: defaults).accent = accent
            XCTAssertNotNil(defaults.object(forKey: "AppleAccentColor"), "\(accent)")
            XCTAssertTrue(seen.insert(defaults.integer(forKey: "AppleAccentColor")).inserted, "\(accent) shares a colour")
        }
    }

    func testABlurKeepsThePicturesShape() throws {
        let picture = try XCTUnwrap(Self.picture(width: 400, height: 200))
        let sharp = try XCTUnwrap(Appearance.blurred(picture, points: 0))
        XCTAssertEqual(sharp.width, 400)
        let soft = try XCTUnwrap(Appearance.blurred(picture, points: 20))
        XCTAssertEqual(soft.width, 400)
        XCTAssertEqual(soft.height, 200)
        // A big picture is blurred at a smaller size, in the same shape.
        let big = try XCTUnwrap(Self.picture(width: 4000, height: 2000))
        let small = try XCTUnwrap(Appearance.blurred(big, points: 20))
        XCTAssertEqual(small.width, 1600)
        XCTAssertEqual(small.height, 800)
    }

    func testAFileThatIsNotAPictureIsRefused() throws {
        let look = Appearance(defaults: defaults)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).txt")
        try Data("not a picture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        look.chooseWallpaper(file)
        XCTAssertNil(look.wallpaperPath)
        XCTAssertNotNil(look.problem)
        XCTAssertEqual(look.backdrop, .desktop, "the backdrop stays as it was")
    }

    private static func picture(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.7, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return context?.makeImage()
    }
}
