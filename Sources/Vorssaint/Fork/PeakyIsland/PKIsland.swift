// SPDX-License-Identifier: GPL-3.0-or-later
// Fork: Peaky's island (MIT, Copyright (c) 2026 Suman Pokharel), brought into Vorssaint.
//
// The island's state: what it shows, how big it is, and when it opens.
// Unlike Peaky, hovering does nothing: only a click (or a swipe, or a file
// drag for the shelf) opens it.

import AppKit
import Combine
import SwiftUI

enum PKIslandTab: Equatable { case home, shelf }

/// What the island is showing right now, highest priority first.
enum PKPresentation: Equatable { case expanded, music, status, pet, idle }

/// The one thing shown left of the notch: a meeting about to start, or the Claude spark.
struct PKStatusItem: Equatable {
    enum Kind: Equatable { case meeting, working }
    let kind: Kind
    let title: String
    let detail: String
    let tint: Color
    let bar: Color?
    var event: NotchCalendarEvent? = nil

    /// The Claude spark sits alone beside the notch; its words are not needed.
    var isGlyph: Bool { kind == .working }
    var titleMax: CGFloat { PKIslandModel.agendaTitleMax }
}

struct PKNotchGeometry {
    let screenFrame: CGRect
    let notch: CGSize
    let isVirtual: Bool

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if let real = Self.realNotch(screen) {
            notch = real
            isVirtual = false
        } else {
            // Peaky's virtual notch for monitors without one: about menu-bar height.
            notch = CGSize(width: 120, height: 24)
            isVirtual = true
        }
    }

    init(notch: CGSize, isVirtual: Bool) {
        screenFrame = .zero
        self.notch = notch
        self.isVirtual = isVirtual
    }

    private static func realNotch(_ screen: NSScreen) -> CGSize? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }
}

final class PKIslandModel: ObservableObject {
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.88)
    static let close = Animation.spring(response: 0.32, dampingFraction: 0.95)
    static let open = Animation.spring(response: 0.28, dampingFraction: 0.84)

    static let petEar: CGFloat = 32

    let geo: PKNotchGeometry

    // Every change also bumps `revision` after it is stored, so SwiftUI's
    // last read always sees the final state (see Peaky's Island.swift).
    @Published private(set) var revision = 0
    @Published private(set) var expanded = false { didSet { revision &+= 1 } }
    @Published var tab: PKIslandTab = .home { didSet { revision &+= 1 } }
    @Published private(set) var musicActive = false { didSet { revision &+= 1 } }
    @Published private(set) var pet: PKPetKind = .none { didSet { revision &+= 1 } }
    @Published var dropTargeted = false { didSet { revision &+= 1 } }
    @Published var fileDragging = false { didSet { revision &+= 1 } }
    var holdShelfUntil = Date.distantPast
    var holdingShelf: Bool { Date() < holdShelfUntil }
    @Published private(set) var shelfCount = 0 { didSet { revision &+= 1 } }
    @Published private(set) var showsScrubber = false { didSet { revision &+= 1 } }
    static let scrubberHeight: CGFloat = 22
    @Published private(set) var agenda: NotchCalendarEvent? { didSet { revision &+= 1 } }
    @Published private(set) var claudeWorking = false { didSet { revision &+= 1 } }

    private var musicHideWork: DispatchWorkItem?
    /// Dev probe only: the states it sets are not replaced by live readings.
    private var frozen = false
    private var bag = Set<AnyCancellable>()

    init(geo: PKNotchGeometry) {
        self.geo = geo
        pet = PKPrefs.pet
        let services = PKServices.shared
        let np = services.nowPlaying
        np.$duration.combineLatest(np.$title)
            .map { d, title in d > 1 && !title.isEmpty }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] on in withAnimation(Self.spring) { self?.showsScrubber = on } }
            .store(in: &bag)
        services.shelf.$items.map(\.count).removeDuplicates()
            .sink { [weak self] n in self?.shelfCount = n }.store(in: &bag)
        // Shown as soon as something plays, held through short pauses so a
        // quick pause or a player switching doesn't make the island jump.
        np.$isPlaying.combineLatest(np.$title)
            .map { playing, title in playing && !title.isEmpty }
            .removeDuplicates()
            .sink { [weak self] playing in
                guard self?.frozen == false else { return }
                self?.musicPlaying(playing)
            }
            .store(in: &bag)
        services.calendar.$soon.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] e in
                guard let self, !self.frozen, e != self.agenda else { return }
                withAnimation(Self.spring) { self.agenda = e }
            }
            .store(in: &bag)
        services.calendar.$tick
            .sink { [weak self] _ in self?.revision &+= 1 }
            .store(in: &bag)
        services.claude.$working.removeDuplicates()
            .sink { [weak self] on in
                guard self?.frozen == false else { return }
                self?.claudeWorking = on
            }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.pet != PKPrefs.pet else { return }
                withAnimation(Self.spring) { self.pet = PKPrefs.pet }
            }
            .store(in: &bag)
    }

    private func musicPlaying(_ playing: Bool) {
        musicHideWork?.cancel()
        if playing {
            guard !musicActive else { return }
            withAnimation(Self.spring) { musicActive = true }
        } else if musicActive {
            let w = DispatchWorkItem { [weak self] in
                withAnimation(Self.close) { self?.musicActive = false }
            }
            musicHideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
        }
    }

    // MARK: What shows

    /// Left of the notch: a meeting in its last minutes before it starts,
    /// then, only when nothing plays, the Claude spark.
    var status: PKStatusItem? {
        if let e = agenda {
            return PKStatusItem(kind: .meeting, title: e.title.isEmpty ? "Meeting" : e.title,
                                detail: PKServices.shared.calendar.relative(e), tint: .white.opacity(0.6),
                                bar: PKCalendar.color(e), event: e)
        }
        if claudeWorking, !musicActive {
            return PKStatusItem(kind: .working, title: "Claude", detail: "working",
                                tint: Color(pkHex: 0xD97757).opacity(0.8), bar: nil)
        }
        return nil
    }

    var presentation: PKPresentation {
        if expanded { return .expanded }
        if musicActive { return .music }
        if status != nil { return .status }
        if pet != .none { return .pet }
        return .idle
    }

    // MARK: Sizing

    func size(for p: PKPresentation) -> CGSize {
        let n = geo.notch, h = n.height
        switch p {
        case .idle:
            return geo.isVirtual ? CGSize(width: n.width, height: 0) : CGSize(width: n.width, height: h)
        case .status:
            return CGSize(width: n.width + statusLeftEar + statusRightEar, height: h)
        case .pet:
            return CGSize(width: n.width + Self.petEar, height: h)
        case .music:
            let ears = musicEars
            return CGSize(width: n.width + ears.left + ears.right, height: h)
        case .expanded:
            let w = expandedWidth
            if tab == .shelf, shelfCount > 0 {
                return CGSize(width: w, height: h + 6 + Self.shelfBarHeight + 6 + shelfGridHeight(width: w) + 14)
            }
            return CGSize(width: w, height: h + 76 + (showsStatusLine ? Self.statusLineHeight : 0)
                                       + (tab == .home && showsScrubber ? Self.scrubberHeight : 0))
        }
    }

    var expandedWidth: CGFloat { max(geo.notch.width + 225, geo.isVirtual ? 360 : 420) }

    /// The meeting gets its own line with Join below the player.
    var showsStatusLine: Bool { status?.kind == .meeting && PKServices.shared.nowPlaying.hasMedia }

    // MARK: Shelf

    static let shelfTile = CGSize(width: 64, height: 56)
    static let shelfGap: CGFloat = 4
    static let shelfBarHeight: CGFloat = 22
    static let shelfMaxRows = 3

    func shelfColumns(width: CGFloat) -> Int {
        max(1, Int((width - 36 + Self.shelfGap) / (Self.shelfTile.width + Self.shelfGap)))
    }

    func shelfGridHeight(width: CGFloat) -> CGFloat {
        let cols = shelfColumns(width: width)
        let rows = min(Self.shelfMaxRows, max(1, (shelfCount + cols - 1) / cols))
        return CGFloat(rows) * Self.shelfTile.height + CGFloat(rows - 1) * Self.shelfGap
    }

    // MARK: Ears (the parts left and right of the hardware notch)

    static let innerGap: CGFloat = 6
    static func artSize(_ h: CGFloat) -> CGFloat { h - (h > 30 ? 14 : 8) }
    static func musicLeftEar(_ h: CGFloat) -> CGFloat { 10 + artSize(h) + innerGap }
    static let musicBarsEar: CGFloat = innerGap + 17 + 12
    static let agendaTitleFont = PKTheme.nsTitle(11)
    static let agendaDetailFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
    static let agendaTitleMax: CGFloat = 86
    static let statusLineHeight: CGFloat = 30

    func xOffset(for p: PKPresentation) -> CGFloat {
        switch p {
        case .pet: return Self.petEar / 2
        case .status: return (statusRightEar - statusLeftEar) / 2
        case .music:
            let ears = musicEars
            return (ears.right - ears.left) / 2
        default: return 0
        }
    }

    /// Music alone: artwork left, bars right. Beside a meeting: the meeting
    /// left, the bars right.
    var musicEars: (left: CGFloat, right: CGFloat) {
        if status != nil { return (statusLeftEar, Self.musicBarsEar) }
        return (Self.musicLeftEar(geo.notch.height), Self.musicBarsEar)
    }

    private var statusDetailWidth: CGFloat {
        guard let s = status else { return 0 }
        return (s.detail as NSString).size(withAttributes: [.font: Self.agendaDetailFont]).width + Self.innerGap + 12
    }

    /// A meeting with the right side free: title left of the notch, time right of it.
    var statusSplit: Bool {
        guard let s = status else { return false }
        return !s.isGlyph && !musicActive
    }

    var statusTitleLimit: CGFloat { status?.titleMax ?? 0 }

    var statusLeftEar: CGFloat {
        guard let s = status else { return 0 }
        if s.isGlyph { return Self.petEar }
        let lead: CGFloat = 3 + 7
        let t = min((s.title as NSString).size(withAttributes: [.font: Self.agendaTitleFont]).width, statusTitleLimit)
        let d = statusSplit ? 0 : 5 + (("· " + s.detail) as NSString).size(withAttributes: [.font: Self.agendaDetailFont]).width
        return (12 + lead + t + d + Self.innerGap).rounded(.up)
    }

    var statusRightEar: CGFloat {
        guard let s = status else { return 0 }
        if s.kind == .working { return 0 }
        return (statusSplit ? statusDetailWidth : 0).rounded(.up)
    }

    func radii(for p: PKPresentation) -> (top: CGFloat, bottom: CGFloat) {
        switch p {
        case .idle, .music, .pet, .status: return (6, PKTheme.compactBottomRadius)
        case .expanded: return (10, PKTheme.expandedBottomRadius)
        }
    }

    // MARK: State changes

    func expand(tab: PKIslandTab? = nil) {
        if let tab { self.tab = tab }
        guard !expanded else { return }
        withAnimation(Self.open) { expanded = true }
    }

    func collapse() {
        guard expanded, !PKShelfCollectionView.quickLookVisible, !PKIslandMenu.isOpen else { return }
        PKNotchPanel.giveBackAll()
        withAnimation(Self.close) {
            expanded = false
            dropTargeted = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.expanded, self.tab != .home else { return }
            self.tab = .home
        }
    }

    func switchTab(forward: Bool) {
        withAnimation(Self.spring) { tab = (tab == .home) == forward ? .shelf : .home }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        holdShelfUntil = Date().addingTimeInterval(5)
        tab = .shelf
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { DispatchQueue.main.async { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            DispatchQueue.main.async {
                guard !urls.isEmpty else { return }
                PKServices.shared.shelf.add(urls)
                self?.tab = .shelf
            }
        }
        return true
    }

    #if VORSSAINT_DEVELOPMENT
    func debugSet(expanded: Bool, tab: PKIslandTab = .home, music: Bool, pet: PKPetKind = .cat,
                  agenda: NotchCalendarEvent? = nil, claude: Bool = false) {
        frozen = true
        self.agenda = agenda
        claudeWorking = claude
        self.tab = tab
        self.expanded = expanded
        musicActive = music
        self.pet = pet
    }
    #endif
}
