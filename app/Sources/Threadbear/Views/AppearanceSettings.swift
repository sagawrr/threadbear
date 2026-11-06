import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Appearance: what's behind the panels, how see-through they
/// are, the accent colour, and the pictures on the Librarian's and
/// Scheduled's pages (Appearance.swift). Unlike the other tabs this is the
/// app's own, so it shows whether or not the runner is connected.
struct AppearanceSettings: View {
    @State private var appearance = Appearance.shared

    var body: some View {
        @Bindable var appearance = appearance
        Form {
            SettingsSection("Backdrop",
                            about: "What's behind the window's panels: nothing, the desktop blurred, or a picture of your own. A picture you choose is copied into Threadbear's folder on this Mac and never leaves it.",
                            ask: "change it for you, or set values the sliders don't reach. They're in this app's defaults, under appearance.") {
                Picker("Behind the panels", selection: $appearance.backdrop) {
                    ForEach(Appearance.Backdrop.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .tip("What shows through the panels")

                LabeledContent("Picture") {
                    HStack(spacing: 8) {
                        if let wallpaper = appearance.wallpaper {
                            Thumbnail(image: wallpaper)
                        }
                        Button("Choose…") { pick { appearance.chooseWallpaper($0) } }
                            .tip("Pick a picture to put behind the panels")
                        if appearance.wallpaperPath != nil {
                            Button("Remove") { appearance.removeWallpaper() }
                                .tip("Take the picture away and delete Threadbear's copy of it")
                        }
                    }
                }

                if appearance.backdrop == .picture, appearance.wallpaper != nil {
                    AppearanceSlider(title: "Blur", value: $appearance.blur, range: Appearance.blurRange,
                                     low: "Sharp", high: "Soft", tip: "How blurred the picture is")
                    AppearanceSlider(title: "Fade", value: $appearance.dim, range: Appearance.dimRange,
                                     low: "Vivid", high: "Faint", tip: "How far the picture fades into the window's own colour")
                }
                if appearance.backdrop != .off {
                    AppearanceSlider(title: "Panels", value: $appearance.panelOpacity, range: Appearance.panelRange,
                                     low: "Glass", high: "Solid", tip: "How much of the backdrop shows through the panels")
                }
            }

            SettingsSection("Accent colour",
                            about: "The colour of buttons, selections and links in Threadbear only. The rest of your Mac keeps its own.",
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

            SettingsSection("Page pictures",
                            about: "The picture at the top of the Librarian's page and of Scheduled's. Without one of your own, each shows the mascot.",
                            ask: "set one from a file you name.") {
                ForEach(Appearance.Slot.allCases) { slot in
                    LabeledContent(slot.title) {
                        HStack(spacing: 8) {
                            if let picture = appearance.picture(slot) {
                                Thumbnail(image: picture)
                            }
                            Button("Choose…") { pick { appearance.choosePicture($0, for: slot) } }
                                .tip("Pick a picture for the \(slot.title.lowercased())")
                            if appearance.hasPicture(slot) {
                                Button("Remove") { appearance.removePicture(slot) }
                                    .tip("Go back to the mascot and delete Threadbear's copy of the picture")
                            }
                        }
                    }
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
    }

    private func pick(_ use: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a picture"
        if panel.runModal() == .OK, let url = panel.url { use(url) }
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
