// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

/// `--mascot-sheet`: a black window with every companion style, and the cat
/// acting out each reaction again every three seconds, for screenshots. It
/// reads and writes no preferences and quits by itself after `--seconds N`
/// (20 by default). It prints the window's rect in screen points from the top
/// left, ready for `screencapture -R`.
enum NotchMascotProbe {
    static let argument = "--mascot-sheet"
    private static let suite = "com.vorssaint.tests.mascot-probe"

    static func runAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments
        let seconds = arguments.firstIndex(of: "--seconds").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 20
        let size = CGSize(width: 820, height: 330)
        let screen = NSScreen.screens.first!
        let origin = CGPoint(x: screen.frame.minX + 60, y: screen.frame.minY + 80)
        let window = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .floating
        window.backgroundColor = .black
        window.isOpaque = true
        window.contentView = NSHostingView(rootView: Sheet().frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        let top = screen.frame.maxY - (origin.y + size.height)
        print("CAPTURE \(Int(origin.x)),\(Int(top)),\(Int(size.width)),\(Int(size.height))")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            exit(0)
        }
        app.run()
        exit(0)
    }

    private struct Sheet: View {
        @State private var tick = 0
        private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
        private static let pulseDefaults: UserDefaults = {
            // A registered default would reach every suite, the marks' too, so
            // the pulse is set in a suite of its own, removed again on exit.
            UserDefaults.standard.register(defaults: [DefaultsKey.notchAgentsIndicator: NotchAgentIndicator.mark.rawValue])
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(NotchAgentIndicator.pulse.rawValue, forKey: DefaultsKey.notchAgentsIndicator)
            return defaults
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    ForEach(NotchMascotStyle.allCases) { style in
                        cell(style.rawValue) {
                            NotchMascotView(look: NotchMascotLook(style: style, shape: .ball, palette: .sky), size: 44)
                        }
                    }
                    ForEach([NotchMascotPalette.pearl, .lemon, .peach, .rose, .lilac, .mint], id: \.self) { palette in
                        cell(palette.rawValue) {
                            NotchMascotView(look: NotchMascotLook(style: .cat, shape: .ball, palette: palette), size: 44)
                        }
                    }
                    cell("sleepy") {
                        NotchMascotView(look: NotchMascotLook(style: .cat, shape: .ball, palette: .sky), mood: .sleepy,
                                        size: 44)
                    }
                }
                HStack(spacing: 18) {
                    ForEach(NotchMascotReaction.allCases, id: \.self) { reaction in
                        cell(reaction.rawValue) {
                            NotchMascotView(look: NotchMascotLook(style: .cat, shape: .ball, palette: .sky), size: 44,
                                            idles: false, reaction: reaction)
                                .id("\(reaction.rawValue)-\(tick)")
                        }
                    }
                }
                HStack(spacing: 24) {
                    ForEach([AgentProvider.claude, .codex, .cursor], id: \.self) { provider in
                        cell("\(provider.rawValue) mark") { NotchAgentGlyph(provider: provider, size: 13) }
                        cell("\(provider.rawValue) pulse") {
                            NotchAgentGlyph(provider: provider, size: 13).defaultAppStorage(Self.pulseDefaults)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .onReceive(timer) { _ in tick += 1 }
        }

        private func cell(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(spacing: 4) {
                content().frame(width: 48, height: 52)
                Text(title).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1).fixedSize()
            }
        }
    }
}
#endif
