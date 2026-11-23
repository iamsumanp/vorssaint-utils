// SPDX-License-Identifier: GPL-3.0-or-later
// Fork: a dev-only sheet of the Peaky-style island's states, for screenshots.

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

/// `--peaky-island-sheet [--seconds N] [--files DIR]`: one window with every
/// state of the Peaky-style island on a wallpaper-grey tile each, with fake
/// music, a meeting 12 minutes away, Claude working and a few shelf files.
/// Reads and writes no preferences. Prints CAPTURE x,y,w,h (points from the
/// top left) for `screencapture -R`, and quits after N seconds (25).
enum PKIslandProbe {
    static let argument = "--peaky-island-sheet"

    static func runAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        let seconds = value("--seconds").flatMap(Double.init) ?? 25
        let files = value("--files").map { dir in
            ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } ?? []

        fake(files: files)
        let size = CGSize(width: 1080, height: 760)
        let screen = NSScreen.screens.first!
        let origin = CGPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
        let window = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .floating
        window.backgroundColor = NSColor(white: 0.16, alpha: 1)
        window.isOpaque = true
        window.contentView = NSHostingView(rootView: Sheet().frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        let top = screen.frame.maxY - (origin.y + size.height)
        print("CAPTURE \(Int(origin.x)),\(Int(top)),\(Int(size.width)),\(Int(size.height))")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
        app.run()
        exit(0)
    }

    static let meeting = NotchCalendarEvent(
        id: "probe", title: "WF Weekly", calendar: "Work", start: Date().addingTimeInterval(12 * 60 - 5),
        end: Date().addingTimeInterval(42 * 60), allDay: false, location: "",
        color: NotchCalendarColor(red: 0.35, green: 0.85, blue: 0.8),
        meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))

    private static func fake(files: [URL]) {
        let music = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first
        let browser = NSWorkspace.shared.frontmostApplication
        var sources: [NotchPlaybackSource] = []
        if let browser {
            sources.append(NotchPlaybackSource(pid: browser.processIdentifier, bundleIdentifier: browser.bundleIdentifier ?? "x",
                                               isMusicApp: false, isPlaying: true, hasTrack: true))
        }
        if let music, music.processIdentifier != browser?.processIdentifier {
            sources.append(NotchPlaybackSource(pid: music.processIdentifier, bundleIdentifier: "com.apple.Music",
                                               isMusicApp: true, isPlaying: false, hasTrack: true))
        }
        PKServices.shared.nowPlaying.debugFake(title: "Selfless (Official Audio)", artist: "The Strokes", playing: true,
                                               duration: 224, artwork: cover(), sources: sources,
                                               shownPID: sources.first?.pid)
        PKServices.shared.calendar.debugFake(meeting)
        PKServices.shared.shelf.debugFake(files)
        PKServices.shared.claude.debugFake(true)
    }

    private static func cover() -> NSImage {
        NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.85, green: 0.35, blue: 0.25, alpha: 1),
                                NSColor(red: 0.25, green: 0.15, blue: 0.45, alpha: 1)])?.draw(in: rect, angle: -60)
            return true
        }
    }

    private struct Tile: Identifiable {
        let id: String
        let model: PKIslandModel
        let height: CGFloat
    }

    private static func model(_ notch: CGSize = CGSize(width: 185, height: 32), virtual: Bool = false,
                              _ configure: (PKIslandModel) -> Void) -> PKIslandModel {
        let m = PKIslandModel(geo: PKNotchGeometry(notch: notch, isVirtual: virtual))
        configure(m)
        return m
    }

    private struct Sheet: View {
        private let compact: [Tile] = [
            Tile(id: "idle · pet", model: PKIslandProbe.model { $0.debugSet(expanded: false, music: false) }, height: 44),
            Tile(id: "music", model: PKIslandProbe.model { $0.debugSet(expanded: false, music: true) }, height: 44),
            Tile(id: "meeting · 12 min", model: PKIslandProbe.model {
                $0.debugSet(expanded: false, music: false, agenda: PKIslandProbe.meeting) }, height: 44),
            Tile(id: "Claude working", model: PKIslandProbe.model {
                $0.debugSet(expanded: false, music: false, claude: true) }, height: 44),
            Tile(id: "music + meeting", model: PKIslandProbe.model {
                $0.debugSet(expanded: false, music: true, agenda: PKIslandProbe.meeting, claude: true) }, height: 44),
            Tile(id: "external · music", model: PKIslandProbe.model(CGSize(width: 120, height: 24), virtual: true) {
                $0.debugSet(expanded: false, music: true) }, height: 36),
        ]
        private let open: [Tile] = [
            Tile(id: "open · player, switcher, meeting", model: PKIslandProbe.model {
                $0.debugSet(expanded: true, music: true, agenda: PKIslandProbe.meeting) }, height: 230),
            Tile(id: "open · shelf", model: PKIslandProbe.model {
                $0.debugSet(expanded: true, tab: .shelf, music: true) }, height: 230),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.fixed(520)), GridItem(.fixed(520))], alignment: .leading, spacing: 14) {
                    ForEach(compact) { tile($0, width: 520) }
                }
                HStack(alignment: .top, spacing: 14) {
                    ForEach(open) { tile($0, width: 520) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
        }

        private func tile(_ t: Tile, width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom)
                    // A menu bar strip, as on screen.
                    Color.white.opacity(0.18).frame(height: t.model.geo.notch.height)
                        .frame(maxHeight: .infinity, alignment: .top)
                    PKIslandView(model: t.model)
                }
                .frame(width: width, height: t.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(t.id).font(.system(size: 10)).foregroundStyle(.gray)
            }
        }
    }
}
#endif
