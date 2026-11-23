// SPDX-License-Identifier: GPL-3.0-or-later
// Fork: Peaky's island (MIT, Copyright (c) 2026 Suman Pokharel), brought into Vorssaint.
// Peaky's building blocks: the notch shape, buttons, scrubber, artwork, bars, marquee, Claude's spark.

import AppKit
import SwiftUI

// MARK: - Shape

/// The notch silhouette: concave "ears" at the top corners, rounded bottom corners.
struct PKNotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = max(0, min(bottomRadius, (rect.height - t) / 1, (rect.width - 2 * t) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// True only while the island is open, so hidden timelines (scrubber, marquee) stop ticking.
private struct PKIslandExpandedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var pkIslandExpanded: Bool {
        get { self[PKIslandExpandedKey.self] }
        set { self[PKIslandExpandedKey.self] = newValue }
    }
}

struct PKChipButton: View {
    let label: String
    let filled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(PKTheme.body(11, .semibold))
                .foregroundStyle(filled ? Color.black : .white.opacity(hover ? 1 : 0.85))
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: PKTheme.tileRadius)
                    .fill(filled ? PKTheme.accent.opacity(hover ? 0.85 : 1) : Color.white.opacity(hover ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PKPixelButton: View {
    let symbol: String
    let size: CGFloat
    let iconSize: CGFloat
    let filled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: PKTheme.tileRadius)
                    .fill(Color.white.opacity(filled ? (hover ? 0.16 : 0.1) : (hover ? 0.08 : 0))))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PKScrubber: View {
    /// Only while the island is open: a hidden bar ticking twice a second cost ~1–2 % CPU all day.
    var ticking = true
    @ObservedObject var np = PKServices.shared.nowPlaying
    /// While dragging: where the knob is (0…1); the track only seeks when you let go.
    @State private var dragging: Double?
    @State private var hover = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !ticking)) { ctx in
            let d = max(np.duration, 1)
            let f = dragging ?? min(max(np.elapsed(at: ctx.date) / d, 0), 1)
            HStack(spacing: 8) {
                Text(Self.time(f * d))
                    .frame(width: 38, alignment: .trailing)
                GeometryReader { g in
                    let w = g.size.width
                    let active = hover || dragging != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: active ? 5 : 3)
                        Capsule().fill(Color.white.opacity(0.85)).frame(width: max(3, w * f), height: active ? 5 : 3)
                        Circle().fill(Color.white)
                            .frame(width: 10, height: 10)
                            .offset(x: w * f - 5)
                            .opacity(active ? 1 : 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in dragging = min(max(v.location.x / max(w, 1), 0), 1) }
                        .onEnded { v in
                            np.seek(to: min(max(v.location.x / max(w, 1), 0), 1) * d)
                            dragging = nil
                        })
                    .animation(.easeOut(duration: 0.12), value: active)
                }
                .onHover { hover = $0 }
                Text(Self.time(d))
                    .frame(width: 38, alignment: .leading)
            }
            .font(PKTheme.mono(10))
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
        }
        .frame(height: PKIslandModel.scrubberHeight - 6)
    }

    /// 75 → "1:15", 3725 → "1:02:05".
    static func time(_ s: Double) -> String {
        let t = Int(s.rounded(.down)), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}


struct PKShelfSwitch: View {
    @ObservedObject var model: PKIslandModel
    @ObservedObject var shelf = PKServices.shared.shelf
    @State private var hover = false

    var body: some View {
        let onShelf = model.tab == .shelf
        Button {
            withAnimation(PKIslandModel.spring) { model.tab = onShelf ? .home : .shelf }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: onShelf ? "house.fill" : "tray.fill")
                    .font(.system(size: 10, weight: .semibold))
                if !onShelf && !shelf.items.isEmpty {
                    Text("\(shelf.items.count)").font(PKTheme.mono(10))
                }
            }
            .foregroundStyle(.white.opacity(hover ? 0.9 : 0.6))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: PKTheme.tileRadius).fill(Color.white.opacity(hover ? 0.14 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(onShelf ? "Back" : "Shelf")
    }
}


struct PKArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    var corner: CGFloat = PKTheme.tileRadius

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

/// Little equaliser bars. With "Bars follow the music" on they move with the sound (LiveAudio); otherwise,
/// or without the permission, they're decoration driven by time.
/// Animated by Core Animation in the render server, so it costs Peaky nothing per frame (a SwiftUI
/// timeline here re-laid-out the whole island 20× a second, ~8% CPU while music played).
struct PKVisualizer: NSViewRepresentable {
    let playing: Bool
    let color: Color
    /// On screen. Only visible bars listen to the sound.
    var active = true

    func makeNSView(context: Context) -> BarsView { BarsView() }
    func updateNSView(_ v: BarsView, context: Context) {
        v.update(playing: playing, color: NSColor(color), listen: false)
    }
    static func dismantleNSView(_ v: BarsView, coordinator: ()) { v.update(playing: false, color: .white, listen: false) }

    final class BarsView: NSView {
        private var bars: [CALayer] = []
        private var playing = false
        private var listening = false
        /// Showing live levels right now (else the decorative bounce).
        private var live = false
        private let durations: [CFTimeInterval] = [0.42, 0.31, 0.53, 0.37]
        private let lows: [CGFloat] = [0.25, 0.35, 0.2, 0.3]
        private static let rest: CGFloat = 0.18

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<4 {
                let l = CALayer()
                l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer?.addSublayer(l)
                bars.append(l)
            }
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let gap: CGFloat = 2.5
            let w = (bounds.width - gap * 3) / 4
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, l) in bars.enumerated() {
                l.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
                l.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
                l.cornerRadius = 1 // pixel style: square-ish blocks
            }
            CATransaction.commit()
            if playing, !live { animate() }
        }

        func update(playing: Bool, color: NSColor, listen: Bool) {
            bars.forEach { $0.backgroundColor = color.cgColor }
            let changed = playing != self.playing
            self.playing = playing
            if listen != listening {
                listening = listen
                if !listen, live { live = false; decorate(); return }
            }
            if changed, !live { decorate() }
        }

        /// From LiveAudio, ~30× a second while listening; nil = no live sound, go back to the bounce.
        func show(_ levels: [Float]?) {
            guard listening else { return }
            guard let levels else {
                if live { live = false; decorate() }
                return
            }
            if !live {
                live = true
                bars.forEach { $0.removeAnimation(forKey: "bounce") }
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(1.0 / 30)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
            for (l, v) in zip(bars, levels) {
                l.transform = CATransform3DMakeScale(1, Self.rest + (1 - Self.rest) * CGFloat(v), 1)
            }
            CATransaction.commit()
        }

        private func decorate() { playing ? animate() : rest() }

        private func animate() {
            for (i, l) in bars.enumerated() {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = lows[i]
                a.toValue = 1.0
                a.duration = durations[i]
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.timeOffset = Double(i) * 0.13
                l.add(a, forKey: "bounce")
            }
        }

        private func rest() {
            for l in bars {
                l.removeAnimation(forKey: "bounce")
                l.transform = CATransform3DMakeScale(1, Self.rest, 1)
            }
        }
    }
}

/// Scrolls the text horizontally when it doesn't fit.
struct PKMarqueeText: View {
    let text: String
    let font: Font
    @Environment(\.pkIslandExpanded) private var active
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let overflow = textWidth > g.size.width
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !overflow || !active)) { ctx in
                let gap: CGFloat = 40
                let cycle = Double(textWidth + gap) / 30 + 2 // 30 pt/s plus a 2s rest
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                let offset = overflow ? -CGFloat(max(0, t - 2) * 30) : 0
                HStack(spacing: gap) {
                    Text(text).font(font).fixedSize()
                        .background(GeometryReader { tg in Color.clear.onAppear { textWidth = tg.size.width }
                            .onChange(of: text) { textWidth = tg.size.width } })
                    if overflow { Text(text).font(font).fixedSize() }
                }
                .fixedSize()
                .offset(x: offset)
                // Wider than its frame, the row would be centred in it; it starts at the leading edge.
                .frame(width: g.size.width, alignment: .leading)
            }
            .frame(width: g.size.width, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: overflow ? [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
            ] : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: 20)
    }
}

struct PKTileIcon: View {
    let symbol: String
    let tint: Color
    let glyph: CGFloat

    var body: some View {
        if symbol == "claude" {
            PKClaudeMark().foregroundStyle(tint)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: PKTheme.tileRadius).fill(tint.opacity(0.22))
                Image(systemName: symbol).font(.system(size: glyph, weight: .bold)).foregroundStyle(tint)
            }
        }
    }
}

/// Claude's spark, taken from the installed Claude app's menu-bar icon (a template image, so it takes any tint).
/// Falls back to the SF sparkle if Claude.app isn't there.
struct PKClaudeMark: View {
    static let image: NSImage? = {
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
            ?? URL(fileURLWithPath: "/Applications/Claude.app")
        let res = app.appendingPathComponent("Contents/Resources")
        for name in ["TrayIconTemplate@3x.png", "TrayIconTemplate@2x.png", "TrayIconTemplate.png"] {
            if let img = NSImage(contentsOf: res.appendingPathComponent(name)) { img.isTemplate = true; return img }
        }
        return nil
    }()

    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "sparkle").resizable().aspectRatio(contentMode: .fit).fontWeight(.bold).padding(2)
        }
    }
}
