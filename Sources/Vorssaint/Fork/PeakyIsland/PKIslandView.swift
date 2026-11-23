// SPDX-License-Identifier: GPL-3.0-or-later
// Fork: Peaky's island (MIT, Copyright (c) 2026 Suman Pokharel), brought into Vorssaint.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every state is laid out once at its own final size and stays in the tree;
/// changing state only animates the black shape (which also clips) and fades
/// layers in or out, as in Peaky.
struct PKIslandView: View {
    @ObservedObject var model: PKIslandModel

    var body: some View {
        let p = model.presentation
        let size = model.size(for: p)
        let r = model.radii(for: p)
        let shape = PKNotchShape(topRadius: r.top, bottomRadius: r.bottom)
        let h = model.geo.notch.height
        let expandedSize = model.size(for: .expanded)

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)

                ZStack(alignment: .top) {
                    layer(p == .pet, size: model.size(for: .pet)) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            PKPetView(kind: model.pet, hovering: false, active: p == .pet)
                                .frame(width: PKIslandModel.petEar, height: h)
                        }
                        .frame(height: h)
                    }
                    layer(p == .status, size: model.size(for: .status)) {
                        PKStatusLiveView(model: model, height: h)
                    }
                    layer(p == .music, size: model.size(for: .music)) {
                        PKMusicLiveView(model: model, height: h, active: p == .music)
                    }
                    PKExpandedView(model: model)
                        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                        .environment(\.pkIslandExpanded, p == .expanded)
                        .opacity(p == .expanded ? 1 : 0)
                        .scaleEffect(p == .expanded ? 1 : 0.92, anchor: .top)
                        .animation(p == .expanded ? .easeOut(duration: 0.22).delay(0.05) : .easeOut(duration: 0.1), value: p)
                        .allowsHitTesting(p == .expanded)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)

                if model.dropTargeted {
                    shape.stroke(PKTheme.accent.opacity(0.8), lineWidth: 2)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            .onTapGesture { if p != .expanded { model.expand() } }
            .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { model.handleDrop($0) }
            // Vorssaint's floating settings button, beside the open island.
            .overlay(alignment: .topTrailing) {
                PKGearButton()
                    .offset(x: PKGearButton.size + PKGearButton.gap, y: h + 6)
                    .opacity(p == .expanded ? 1 : 0)
                    .scaleEffect(p == .expanded ? 1 : 0.6, anchor: .leading)
                    .animation(p == .expanded ? .easeOut(duration: 0.22).delay(0.1) : .easeOut(duration: 0.08), value: p)
                    .allowsHitTesting(p == .expanded)
            }
        }
        .offset(x: model.xOffset(for: p))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(p == .expanded ? PKIslandModel.open : PKIslandModel.spring, value: p)
        .environment(\.colorScheme, .dark)
    }

    private func layer<C: View>(_ visible: Bool, size: CGSize, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: size.width, height: size.height, alignment: .top)
            .opacity(visible ? 1 : 0)
            .animation(visible ? .easeOut(duration: 0.2).delay(0.04) : .easeOut(duration: 0.08), value: visible)
            .allowsHitTesting(false)
    }
}

/// The floating gear: Vorssaint's Settings, on the Dynamic Island page.
struct PKGearButton: View {
    static let size: CGFloat = 30
    static let gap: CGFloat = 8
    @State private var hover = false

    var body: some View {
        Button {
            PKIslands.shared.controllers.forEach { $0.model.collapse() }
            SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
            (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.75))
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(Color.black))
                .overlay(Circle().strokeBorder(Color.white.opacity(hover ? 0.22 : 0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Island settings")
    }
}

// MARK: - Compact states

struct PKMusicLiveView: View {
    @ObservedObject var model: PKIslandModel
    let height: CGFloat
    var active = true
    @ObservedObject var np = PKServices.shared.nowPlaying

    var body: some View {
        HStack(spacing: 0) {
            // A meeting about to start takes the left side; music keeps its bars.
            if let s = model.status {
                PKStatusSlot(item: s, titleLimit: model.statusTitleLimit)
                    .padding(.leading, 12)
                    .frame(width: model.statusLeftEar, alignment: .leading)
            } else {
                PKArtworkView(image: np.artwork, size: PKIslandModel.artSize(height))
                    .padding(.leading, 10)
            }
            Spacer(minLength: 0)
            PKVisualizer(playing: np.isPlaying, color: .white, active: active)
                .frame(width: 17, height: height * 0.38)
                .padding(.trailing, 12)
        }
        .frame(height: height)
    }
}

/// Colour bar (or Claude's spark), title, "· 12 min".
struct PKStatusSlot: View {
    let item: PKStatusItem
    var showDetail = true
    var compact = false
    var titleLimit: CGFloat? = nil

    var body: some View {
        if item.kind == .working, compact {
            PKTileIcon(symbol: "claude", tint: item.tint, glyph: 8.5)
                .frame(width: 20, height: 20)
        } else {
            HStack(spacing: 5) {
                if item.kind == .working {
                    PKTileIcon(symbol: "claude", tint: item.tint, glyph: 8.5)
                        .frame(width: 16, height: 16)
                        .padding(.trailing, 1)
                } else if let bar = item.bar {
                    RoundedRectangle(cornerRadius: 1).fill(bar).frame(width: 3, height: 14)
                        .padding(.trailing, 2)
                }
                Text(item.title)
                    .font(Font(PKIslandModel.agendaTitleFont))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: titleLimit ?? item.titleMax, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if showDetail {
                    Text("· " + item.detail)
                        .font(Font(PKIslandModel.agendaDetailFont))
                        .foregroundStyle(item.tint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

/// The left slot on its own (nothing playing): the meeting with its time
/// right of the notch, or Claude's spark alone.
struct PKStatusLiveView: View {
    @ObservedObject var model: PKIslandModel
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let s = model.status {
                if s.isGlyph {
                    PKStatusSlot(item: s, compact: true)
                        .padding(.trailing, 4)
                        .frame(width: model.statusLeftEar, height: height, alignment: .trailing)
                } else {
                    PKStatusSlot(item: s, showDetail: !model.statusSplit, titleLimit: model.statusTitleLimit)
                        .padding(.leading, 12)
                        .frame(width: model.statusLeftEar, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            if let s = model.status, !s.isGlyph, model.statusSplit {
                Text(s.detail)
                    .font(Font(PKIslandModel.agendaDetailFont))
                    .foregroundStyle(s.tint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 12)
            }
        }
        .frame(height: height)
    }
}

/// The meeting's own line in the open island, with Join.
struct PKStatusLine: View {
    let item: PKStatusItem

    var body: some View {
        HStack(spacing: 8) {
            PKStatusSlot(item: item, titleLimit: 250)
            Spacer(minLength: 6)
            if let e = item.event, PKServices.shared.calendar.canJoin(e) {
                PKChipButton(label: "Join", filled: true) { PKServices.shared.calendar.join(e) }
            }
        }
        .frame(height: PKIslandModel.statusLineHeight - 6)
    }
}

// MARK: - Expanded

/// The open island. Swipe sideways for the shelf.
struct PKExpandedView: View {
    @ObservedObject var model: PKIslandModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if !model.showsStatusLine { PKJoinChip(model: model) }
                Spacer()
                if model.tab == .home { PKSourceSwitcher() }
                PKShelfSwitch(model: model)
            }
            .padding(.horizontal, 16)
            .frame(height: model.geo.notch.height)
            Group {
                switch model.tab {
                case .home:
                    VStack(spacing: 6) {
                        PKPlayerRow(model: model, open: model.expanded)
                        if model.showsStatusLine, let s = model.status { PKStatusLine(item: s) }
                    }
                case .shelf: PKShelfView(model: model)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// One small icon per player that has something loaded (a browser and Music,
/// say), shown only when there are two or more: the bright one is on screen,
/// a click shows another.
struct PKSourceSwitcher: View {
    @ObservedObject var np = PKServices.shared.nowPlaying

    var body: some View {
        if np.sources.count > 1 {
            HStack(spacing: 2) {
                ForEach(np.sources, id: \.pid) { source in
                    PKSourceIcon(source: source, shown: source.pid == np.shownPID)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: PKTheme.tileRadius).fill(Color.white.opacity(0.06)))
        }
    }
}

private struct PKSourceIcon: View {
    let source: NotchPlaybackSource
    let shown: Bool
    @State private var hover = false
    private var np: PKNowPlaying { PKServices.shared.nowPlaying }

    var body: some View {
        Button { np.show(source) } label: {
            Group {
                if let icon = np.icon(for: source) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 14, height: 14)
            .opacity(shown ? 1 : (hover ? 0.75 : 0.4))
            .frame(width: 20, height: 18)
            .background(RoundedRectangle(cornerRadius: PKTheme.tileRadius - 1)
                .fill(Color.white.opacity(shown ? 0.14 : 0)))
            .overlay(alignment: .bottom) {
                if source.isPlaying {
                    Rectangle().fill(PKTheme.accent).frame(width: 6, height: 1.5).offset(y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(np.name(for: source))
    }
}

struct PKPlayerRow: View {
    @ObservedObject var model: PKIslandModel
    var open = true
    @ObservedObject var np = PKServices.shared.nowPlaying

    var body: some View {
        if np.hasMedia {
            VStack(spacing: 6) {
                player
                if np.duration > 1 { PKScrubber(ticking: open) }
            }
        } else {
            PKIdleRow(model: model)
        }
    }

    private var player: some View {
        HStack(spacing: 12) {
            PKArtworkView(image: np.artwork, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if let icon = np.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16).offset(x: 4, y: 4)
                    }
                }
                .onTapGesture { np.openSourceApp() }
            VStack(alignment: .leading, spacing: 3) {
                PKMarqueeText(text: np.title, font: PKTheme.title(15))
                    .foregroundStyle(.white)
                if !np.subtitle.isEmpty {
                    Text(np.subtitle)
                        .font(PKTheme.body(12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                PKPixelButton(symbol: "backward.fill", size: 36, iconSize: 13, filled: false) { np.previous() }
                PKPixelButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 40, iconSize: 16, filled: true) { np.togglePlayPause() }
                PKPixelButton(symbol: "forward.fill", size: 36, iconSize: 13, filled: false) { np.next() }
            }
        }
    }
}

/// Top-left of the open island while a meeting can be joined.
struct PKJoinChip: View {
    @ObservedObject var model: PKIslandModel
    @ObservedObject var cal = PKServices.shared.calendar

    var body: some View {
        if let e = model.agenda ?? cal.next, cal.canJoin(e) {
            Button { cal.join(e) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "video.fill").font(.system(size: 9, weight: .semibold))
                    Text("Join").font(PKTheme.body(11, .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: PKTheme.tileRadius).fill(PKTheme.accent))
            }
            .buttonStyle(.plain)
            .help(e.title)
        }
    }
}

/// Nothing playing: today's date and the next event.
struct PKIdleRow: View {
    @ObservedObject var model: PKIslandModel
    @ObservedObject var cal = PKServices.shared.calendar

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(PKTheme.title(10))
                    .foregroundStyle(PKTheme.accent)
                Text(Date.now.formatted(.dateTime.day()))
                    .font(PKTheme.mono(22, .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40)
            Group {
                if let e = model.agenda ?? cal.next {
                    PKEventRow(event: e)
                } else {
                    Text("Nothing playing").font(PKTheme.body(12)).foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 56)
    }
}

struct PKEventRow: View {
    let event: NotchCalendarEvent

    private var timeText: String {
        let now = Date()
        if event.allDay { return "All day" }
        if event.start <= now { return "Now · until " + event.end.formatted(date: .omitted, time: .shortened) }
        let mins = Int(event.start.timeIntervalSince(now) / 60)
        let prefix = Calendar.current.isDateInToday(event.start) ? "" : "Tomorrow "
        if mins < 60, prefix.isEmpty { return "In " + NotchCalendarSupport.countdownText(until: event.start, now: now) }
        return prefix + event.start.formatted(date: .omitted, time: .shortened) + " – "
            + event.end.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(PKCalendar.color(event)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(PKTheme.title(12)).foregroundStyle(.white).lineLimit(1)
                Text(timeText).font(PKTheme.mono(10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
    }
}
