import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Appearance, this fork's own tab (Appearance.swift). Nothing
/// here is on until you turn it on: out of the box it's Threadbear as it
/// comes. Each part changes on its own (the background and how see-through
/// the panels are, the accent colour, a picture of yours in place of the
/// bear, the page pictures and the icon), and one button puts it all back.
/// Unlike the other tabs this is the app's own, so it shows whether or not
/// the runner is connected.
struct AppearanceSettings: View {
    @State private var appearance = Appearance.shared
    @State private var confirmingRestore = false

    var body: some View {
        @Bindable var appearance = appearance
        Form {
            SettingsSection("Background",
                            about: "What's behind the window's panels: nothing (the original), the desktop blurred, or a picture of your own. A picture you choose is copied into Threadbear's folder on this Mac and never leaves it.",
                            ask: "change it for you, or set values the sliders don't reach. They're in this app's defaults, under appearance.") {
                Picker("Behind the panels", selection: $appearance.backdrop) {
                    ForEach(Appearance.Backdrop.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .tip("Original is the plain window. Desktop blur and Picture show through the panels")

                PictureRow(title: "Picture",
                           detail: appearance.backdrop == .picture && appearance.wallpaperPath == nil
                               ? "Choose one to show it behind the panels"
                               : "Choosing one switches the background to Picture",
                           image: appearance.wallpaper,
                           has: appearance.wallpaperPath != nil,
                           removeTitle: "Remove",
                           choose: { appearance.chooseWallpaper($0) },
                           remove: { appearance.removeWallpaper() })

                if appearance.backdrop == .picture, appearance.wallpaper != nil {
                    AppearanceSlider(title: "Blur", value: $appearance.blur, range: Appearance.blurRange,
                                     low: "Sharp", high: "Soft", tip: "How blurred the picture is. Softer is easier to read over")
                    AppearanceSlider(title: "Fade", value: $appearance.dim, range: Appearance.dimRange,
                                     low: "Vivid", high: "Faint", tip: "How far the picture fades into the window's own colour. Fainter is easier to read over")
                }
                if appearance.backdrop == .desktop || (appearance.backdrop == .picture && appearance.wallpaper != nil) {
                    AppearanceSlider(title: "Panels", value: $appearance.panelOpacity, range: Appearance.panelRange,
                                     low: "Glass", high: "Solid", tip: "How much of the background shows through the panels. Solid hides it")
                }
            }

            SettingsSection("Accent colour",
                            about: "The colour of buttons, selections and links in Threadbear only. The first swatch is your Mac's own, the original.",
                            ask: "pick one for you.") {
                HStack(spacing: 10) {
                    ForEach(Appearance.Accent.allCases) { accent in
                        AccentSwatch(accent: accent, selected: appearance.accent == accent) { appearance.accent = accent }
                    }
                }
                .padding(.vertical, 2)
                if appearance.accent != appearance.accentAtLaunch {
                    HStack {
                        Text("\(appearance.accent.title) shows the next time Threadbear opens.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reopen Now") {
                            AppUpdate.relaunchAfterExit(Bundle.main.bundleURL)
                            NSApp.terminate(nil)
                        }
                        .tip("Quit Threadbear and open it again with the new colour")
                    }
                }
            }

            SettingsSection("Pictures",
                            about: "A picture of your own in place of Threadbear's: the bear, its cub, the two page pictures and the app's icon. Any picture works. A plain photo is cropped to a circle for the bear and to a rounded tile for the icon; one with a see-through background is shown whole. Each is copied into Threadbear's folder on this Mac and never leaves it.",
                            ask: "set one from a file you name, or cut a character out of a picture for you.") {
                ForEach(Appearance.Slot.allCases) { slot in
                    PictureRow(title: slot.title, detail: slot.detail,
                               image: appearance.picture(slot),
                               has: appearance.hasPicture(slot),
                               choose: { appearance.choosePicture($0, for: slot) },
                               remove: { appearance.removePicture(slot) })
                }
                PictureRow(title: "App icon",
                           detail: "On the Dock straight away, and in Finder from Threadbear's next update",
                           image: appearance.icon,
                           has: appearance.icon != nil,
                           choose: { appearance.chooseIcon($0) },
                           remove: { appearance.removeIcon() })
            }

            Section {
                HStack {
                    Text(appearance.isOriginal ? "This is Threadbear's original look." : "Put everything on this page back as it came.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore the Original Look…") { confirmingRestore = true }
                        .disabled(appearance.isOriginal)
                        .tip("No background, your Mac's accent, the bear, and Threadbear's own pictures and icon")
                }
            }

            if let problem = appearance.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .scrollIndicators(.never)
        .scrollDisabled(true)
        .confirmationDialog("Restore Threadbear's original look?", isPresented: $confirmingRestore) {
            Button("Restore") { appearance.restoreOriginal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The background, accent colour, pictures and icon go back to Threadbear's own. Threadbear's copies of your pictures are deleted; the files you chose them from are not touched.")
        }
    }
}

/// One picture you can set: what it's for, the one in use, and Choose and
/// (once there's one) a button back to Threadbear's own.
private struct PictureRow: View {
    let title: String
    let detail: String
    let image: NSImage?
    let has: Bool
    var removeTitle = "Use Original"
    let choose: (URL) -> Void
    let remove: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let image {
                    Thumbnail(image: image)
                }
                Button("Choose…") { pick() }
                    .tip("Pick a picture for: \(title)")
                if has {
                    Button(removeTitle) { remove() }
                        .tip("Go back to Threadbear's own and delete its copy of your picture")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a picture for: \(title)"
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }
}

private struct Thumbnail: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

private struct AppearanceSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let low: String
    let high: String
    let tip: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(low).font(.caption).foregroundStyle(.secondary)
                Slider(value: $value, in: range)
                    .frame(width: 180)
                    .accessibilityLabel(title)
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
            .tip(tip)
        }
    }
}

private struct AccentSwatch: View {
    let accent: Appearance.Accent
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            ZStack {
                if accent == .system {
                    // The Mac's own: all the colours at once, as System
                    // Settings draws "Multicolour".
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red], center: .center))
                } else {
                    Circle().fill(accent.swatch)
                }
                if selected {
                    Circle().fill(.white).frame(width: 7, height: 7)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tip(accent.title)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
