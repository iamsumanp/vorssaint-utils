// SPDX-License-Identifier: GPL-3.0-or-later
// Fork: Peaky's island (MIT, Copyright (c) 2026 Suman Pokharel), brought into Vorssaint.
//
// Peaky's views read `PKServices.shared`; here those are thin adapters over
// Vorssaint's own services: its music reader (every player, with the source
// switcher), its calendar and meeting links, its shelf and its agent usage.

import AppKit
import Combine
import SwiftUI

/// Fork preferences for the Peaky-style island.
enum PKPrefs {
    static var pet: PKPetKind {
        PKPetKind(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.forkPeakyIslandPet) ?? "") ?? .cat
    }
}

final class PKServices {
    static let shared = PKServices()
    let nowPlaying = PKNowPlaying()
    let calendar = PKCalendar()
    let shelf = PKShelfStore()
    let claude = PKClaude()
}

// MARK: - Now playing

/// Vorssaint's music reading in the shape Peaky's player draws.
final class PKNowPlaying: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var sources: [NotchPlaybackSource] = []
    @Published private(set) var shownPID: Int32?
    @Published private(set) var sourceIsAutomatic = true

    private var playback: NotchPlayback?
    private var bag = Set<AnyCancellable>()
    private var fake = false

    var subtitle: String { [artist, album].first { !$0.isEmpty } ?? "" }
    var hasMedia: Bool { !title.isEmpty }
    /// Seen as playing by the compact island (a paused song folds away).
    var recentlyActive: Bool { hasMedia }

    init() {
        let music = NotchMusicService.shared
        music.$playback.combineLatest(music.$artwork, music.$sources, music.$sourceIsAutomatic)
            .receive(on: RunLoop.main)
            .sink { [weak self] playback, artwork, sources, automatic in
                self?.apply(playback, artwork: artwork, sources: sources, automatic: automatic)
            }
            .store(in: &bag)
    }

    private func apply(_ playback: NotchPlayback?, artwork: NSImage?, sources: [NotchPlaybackSource], automatic: Bool) {
        guard !fake else { return }
        self.playback = playback
        let track = playback?.track
        set(\.title, track?.title ?? "")
        set(\.artist, track?.artist ?? "")
        set(\.album, track?.album ?? "")
        set(\.duration, playback?.duration ?? 0)
        set(\.isPlaying, playback?.isPlaying ?? false)
        if self.artwork !== artwork { self.artwork = artwork }
        set(\.sources, sources)
        set(\.sourceIsAutomatic, automatic)
        set(\.shownPID, track?.appPID)
        let icon = track?.appPID.flatMap { Self.app(pid: $0, bundle: track?.appBundleIdentifier)?.icon }
        if appIcon !== icon { appIcon = icon }
    }

    private func set<T: Equatable>(_ key: ReferenceWritableKeyPath<PKNowPlaying, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func elapsed(at date: Date = Date()) -> Double {
        if fake { return duration * 0.38 }
        return playback?.position(at: date) ?? 0
    }

    func togglePlayPause() { NotchMusicService.shared.send(.toggle) }
    func next() { NotchMusicService.shared.send(.next) }
    func previous() { NotchMusicService.shared.send(.previous) }

    func seek(to seconds: Double) {
        guard let playback else { return }
        NotchMusicService.shared.seek(to: seconds, in: playback.track, context: playback.commandContext)
    }

    func openSourceApp() {
        if let track = playback?.track { RadialNowPlayingApplication.open(track) }
    }

    /// Shows this player; the one shown, chosen by hand, goes back to Automatic.
    func show(_ source: NotchPlaybackSource) {
        if source.pid == shownPID {
            if !sourceIsAutomatic { NotchMusicService.shared.selectSource(nil) }
        } else {
            NotchMusicService.shared.selectSource(source.selection)
        }
    }

    func icon(for source: NotchPlaybackSource) -> NSImage? {
        Self.app(pid: source.pid, bundle: source.bundleIdentifier)?.icon
    }

    private static func app(pid: Int32, bundle: String?) -> NSRunningApplication? {
        RadialNowPlayingApplication.playerApplication(bundleIdentifier: bundle, pid: pid)
    }

    func name(for source: NotchPlaybackSource) -> String {
        source.displayName ?? Self.app(pid: source.pid, bundle: source.bundleIdentifier)?.localizedName ?? source.bundleIdentifier
    }

    #if VORSSAINT_DEVELOPMENT
    func debugFake(title: String, artist: String, playing: Bool, duration: Double, artwork: NSImage?,
                   sources: [NotchPlaybackSource], shownPID: Int32?) {
        fake = true
        self.title = title; self.artist = artist; isPlaying = playing; self.duration = duration
        self.artwork = artwork; self.sources = sources; self.shownPID = shownPID
        appIcon = shownPID.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
    }
    #endif
}

// MARK: - Calendar

/// The meeting the closed island shows: Vorssaint's countdown, within the
/// lead time chosen in Settings (15 minutes for Suman), before it starts.
final class PKCalendar: ObservableObject {
    @Published private(set) var soon: NotchCalendarEvent?
    @Published private(set) var next: NotchCalendarEvent?
    @Published private(set) var tick = 0
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private var fake = false

    init() {
        let service = NotchCalendarService.shared
        service.$countdown.combineLatest(service.$events)
            .receive(on: RunLoop.main)
            .sink { [weak self] countdown, events in self?.apply(countdown, events: events) }
            .store(in: &bag)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.apply(NotchCalendarService.shared.countdown, events: NotchCalendarService.shared.events)
            self.tick &+= 1
        }
        timer?.tolerance = 3
    }

    private func apply(_ countdown: NotchCalendarCountdown?, events: [NotchCalendarEvent]) {
        guard !fake else { return }
        let now = Date()
        let upcoming = countdown.flatMap { !$0.ongoing && $0.event.start > now ? $0.event : nil }
        if upcoming != soon { withAnimation(PKIslandModel.spring) { soon = upcoming } }
        let following = events.first { !$0.allDay && $0.end > now }
        if following != next { next = following }
    }

    /// "12 min", whole minutes as the island reads a meeting.
    func relative(_ event: NotchCalendarEvent) -> String {
        NotchCalendarSupport.countdownText(until: event.start, now: Date())
    }

    func canJoin(_ event: NotchCalendarEvent) -> Bool { fake ? true : NotchMeetingSupport.canJoin(event, at: Date()) }
    func join(_ event: NotchCalendarEvent) { _ = NotchMeetingSupport.join(event) }

    static func color(_ event: NotchCalendarEvent) -> Color {
        Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue)
    }

    #if VORSSAINT_DEVELOPMENT
    func debugFake(_ event: NotchCalendarEvent?) {
        fake = true
        soon = event
        next = event
    }
    #endif
}

// MARK: - Shelf

/// Vorssaint's shelf as the list of file URLs Peaky's grid shows.
final class PKShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    /// Files added in the last few seconds, highlighted.
    @Published private(set) var justAdded = Set<URL>()
    private var ids: [URL: UUID] = [:]
    private var bag = Set<AnyCancellable>()
    private var fake = false

    init() {
        ShelfService.shared.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in self?.apply(items) }
            .store(in: &bag)
    }

    private func apply(_ shelfItems: [ShelfService.Item]) {
        guard !fake else { return }
        var urls: [URL] = []
        var ids: [URL: UUID] = [:]
        func walk(_ item: ShelfService.Item) {
            switch item.payload {
            case .file(let url): if ids[url] == nil { urls.append(url); ids[url] = item.id }
            case .batch(let items): items.forEach(walk)
            case .text, .link: break
            }
        }
        shelfItems.forEach(walk)
        let added = Set(urls).subtracting(items)
        self.ids = ids
        if urls != items { items = urls }
        guard !added.isEmpty, !items.isEmpty else { return }
        justAdded.formUnion(added)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.justAdded.subtract(added) }
    }

    func add(_ urls: [URL]) { ShelfService.shared.addFiles(urls) }

    func remove(_ url: URL) {
        guard let id = ids[url] else { return }
        ShelfService.shared.removeItem(id)
    }

    #if VORSSAINT_DEVELOPMENT
    func debugFake(_ urls: [URL]) { fake = true; items = urls }
    #endif
}

// MARK: - Claude

/// Whether an agent is working right now; the island shows Peaky's Claude spark.
final class PKClaude: ObservableObject {
    @Published private(set) var working = false
    private var bag = Set<AnyCancellable>()
    private var fake = false

    init() {
        AgentUsageService.shared.$snapshot
            .map { !$0.live.isEmpty }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] on in
                guard let self, !self.fake, on != self.working else { return }
                withAnimation(PKIslandModel.spring) { self.working = on }
            }
            .store(in: &bag)
    }

    #if VORSSAINT_DEVELOPMENT
    func debugFake(_ on: Bool) { fake = true; working = on }
    #endif
}
