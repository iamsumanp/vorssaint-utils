// SPDX-License-Identifier: GPL-3.0-or-later
// Fork: Peaky's island (MIT, Copyright (c) 2026 Suman Pokharel), brought into Vorssaint.

import AppKit
import Combine
import SwiftUI

/// Borderless, transparent panel above the menu bar, covering the notch.
final class PKNotchPanel: NSPanel {
    init(frame: NSRect, overFullscreen: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        collectionBehavior = overFullscreen ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                                            : [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    private var keyboardAllowed = false
    override var canBecomeKey: Bool { keyboardAllowed }

    func takeKeyboard() {
        keyboardAllowed = true
        if !isKeyWindow { makeKey() }
    }

    func giveBackKeyboard() {
        guard keyboardAllowed else { return }
        keyboardAllowed = false
        guard isKeyWindow else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            orderOut(nil)
            orderFrontRegardless()
        }
    }

    static func giveBackAll() {
        NSApp.windows.compactMap { $0 as? PKNotchPanel }.forEach { $0.giveBackKeyboard() }
    }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class PKFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One island per screen. The panel is click-through everywhere except over
/// the island, so the menu bar keeps working. Hovering changes nothing: it
/// only lets the island take the click. An open island closes when the
/// pointer leaves it, as Peaky's does; a shelf with files waits for a click
/// outside.
final class PKNotchController {
    static let canvas = CGSize(width: 800, height: 320)

    let screen: NSScreen
    let model: PKIslandModel
    let panel: PKNotchPanel
    let overFullscreen: Bool
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var pollTimer: DispatchSourceTimer?
    private var watcher: DispatchSourceTimer?
    private var leaveWork: DispatchWorkItem?
    private var spaceObserver: NSObjectProtocol?
    private var idleDragCount = NSPasteboard(name: .drag).changeCount
    private var fileDragActive = false
    private var inside = false
    private var locked = false
    private var mouse: CGPoint { NSEvent.mouseLocation }

    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var scrollInContent = false
    private var swipeFired = false
    private var lastWheel = Date.distantPast

    init(screen: NSScreen, overFullscreen: Bool) {
        self.screen = screen
        self.overFullscreen = overFullscreen
        model = PKIslandModel(geo: PKNotchGeometry(screen: screen))
        let f = screen.frame
        let rect = NSRect(x: f.midX - Self.canvas.width / 2, y: f.maxY - Self.canvas.height,
                          width: Self.canvas.width, height: Self.canvas.height)
        panel = PKNotchPanel(frame: rect, overFullscreen: overFullscreen)
        let host = PKFirstMouseHostingView(rootView: PKIslandView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: rect.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        if overFullscreen { PKNotchSpace.shared.add(panel) } else { startKeepingOffFullscreen() }
        installMonitors()
        startWatcher()
        model.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in self?.updateMouse() }
            .store(in: &bag)
        // Opened without the pointer on it (a swipe overshoot, a drop): close
        // again unless the pointer comes over.
        model.$expanded
            .filter { $0 }
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    guard let self, self.model.expanded, !self.inside, !self.shelfSticky else { return }
                    self.model.collapse()
                }
            }
            .store(in: &bag)
    }

    private var shelfSticky: Bool {
        model.expanded && model.tab == .shelf && (model.shelfCount > 0 || model.holdingShelf || fileDragActive)
    }

    func collapseIfMouseLeft() {
        updateMouse()
        if model.expanded, !shelfSticky, !hitRect.contains(mouse) { model.collapse() }
    }

    func setLocked(_ locked: Bool) {
        self.locked = locked
        if locked {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            if overFullscreen { PKNotchSpace.shared.add(panel) }
        }
    }

    private func startKeepingOffFullscreen() {
        let uuid = NotchDisplayChoices.uuid(screen.notchDisplayID) ?? ""
        let apply = { [weak self] in
            guard let self else { return }
            PKNotchSpace.shared.keepOffFullscreenSpaces(self.panel, displayUUID: uuid)
        }
        apply()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in apply() }
    }

    func tearDown() {
        pollTimer?.cancel()
        watcher?.cancel()
        if let o = spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        PKNotchSpace.shared.remove(panel)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Hit testing

    private func islandRect(_ p: PKPresentation) -> CGRect {
        let s = model.size(for: p)
        let f = screen.frame
        return CGRect(x: f.midX - s.width / 2 + model.xOffset(for: p), y: f.maxY - s.height, width: s.width, height: s.height)
    }

    private var hitRect: CGRect {
        let p = model.presentation
        var r: CGRect
        switch p {
        case .idle:
            let n = model.geo.notch
            let f = screen.frame
            r = CGRect(x: f.midX - n.width / 2, y: f.maxY - n.height, width: n.width, height: n.height).insetBy(dx: -6, dy: 0)
        case .expanded:
            r = islandRect(p).insetBy(dx: -8, dy: -8)
            // The floating settings button beside it.
            r.size.width += PKGearButton.size + PKGearButton.gap
        default:
            r = islandRect(p).insetBy(dx: -4, dy: -4)
        }
        r.size.height += displayAbove ? 36 : 4
        return r
    }

    private lazy var displayAbove: Bool = {
        let f = screen.frame
        return NSScreen.screens.contains { s in
            s !== screen && abs(s.frame.minY - f.maxY) < 2 && s.frame.minX < f.midX + 200 && s.frame.maxX > f.midX - 200
        }
    }()

    private var dropZone: CGRect {
        let r = islandRect(.expanded)
        return CGRect(x: r.minX - 30, y: r.minY - 90, width: r.width + 60, height: r.height + 120)
    }

    // MARK: Mouse

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.mouseEvent() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in self?.mouseEvent(); return e }) {
            monitors.append(m)
        }
        // A click anywhere else closes the sticky shelf.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            guard let self, self.model.expanded, !self.hitRect.contains(self.mouse) else { return }
            self.model.collapse()
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            return self.scroll(e) ? nil : e
        }) {
            monitors.append(m)
        }
    }

    private func mouseEvent() {
        updateMouse()
        if nearIsland(mouse) { startTracking() }
    }

    /// A cheap 4 Hz check notices the pointer (or a file drag) coming near.
    private func startWatcher() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 { self.idleDragCount = NSPasteboard(name: .drag).changeCount }
            if self.nearIsland(self.mouse) { self.startTracking() }
        }
        t.resume()
        watcher = t
    }

    private func updateFileDrag() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { fileDragActive = false; return }
        guard !fileDragActive else { return }
        let drag = NSPasteboard(name: .drag)
        if drag.changeCount != idleDragCount, drag.types?.contains(.fileURL) == true { fileDragActive = true }
    }

    private var wantsShelf: Bool { fileDragActive && !model.expanded && dropZone.contains(mouse) }

    private func startTracking() {
        guard pollTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let wasDragging = self.fileDragActive
            self.updateFileDrag()
            if self.fileDragActive != wasDragging { self.model.fileDragging = self.fileDragActive }
            self.updateMouse()
            if !self.inside, !self.nearIsland(self.mouse) {
                self.pollTimer?.cancel()
                self.pollTimer = nil
            }
        }
        t.resume()
        pollTimer = t
    }

    private func nearIsland(_ p: CGPoint) -> Bool {
        islandRect(.expanded).insetBy(dx: -120, dy: -120).contains(p)
    }

    private var cursorInside: Bool {
        if locked { return false }
        let p = mouse
        return hitRect.contains(p) || (fileDragActive && model.expanded && dropZone.contains(p))
    }

    private func updateMouse() {
        if wantsShelf { model.expand(tab: .shelf) }
        let now = cursorInside
        if panel.ignoresMouseEvents == now { panel.ignoresMouseEvents = !now }
        guard now != inside else { return }
        inside = now
        if now {
            leaveWork?.cancel()
        } else if model.expanded {
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.shelfSticky, !self.inside, !self.hitRect.contains(self.mouse) else { return }
                self.model.collapse()
            }
            leaveWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: w)
        }
    }

    // MARK: Swipes

    private func overScrollableContent(_ e: NSEvent) -> Bool {
        guard model.expanded, let root = panel.contentView,
              let hit = root.hitTest(root.convert(e.locationInWindow, from: nil)) else { return false }
        var v: NSView? = hit
        while let view = v {
            if let sv = view as? NSScrollView, let doc = sv.documentView,
               doc.frame.height > sv.contentSize.height + 1 { return true }
            v = view.superview
        }
        return false
    }

    /// Two-finger swipes on the island: down opens, up closes, sideways
    /// switches the tab (open) or the song (closed).
    private func scroll(_ e: NSEvent) -> Bool {
        if e.phase == .began || e.phase == .mayBegin || (e.phase.isEmpty && e.momentumPhase.isEmpty) {
            scrollInContent = overScrollableContent(e)
        }
        if scrollInContent { return false }
        if !e.momentumPhase.isEmpty { return true }
        if e.phase.isEmpty {
            guard Date().timeIntervalSince(lastWheel) > 0.4, abs(e.scrollingDeltaY) > 0.5 else { return true }
            lastWheel = Date()
            if e.scrollingDeltaY < 0 { model.expand() } else { model.collapse() }
            return true
        }
        if e.phase == .began || e.phase == .mayBegin { scrollX = 0; scrollY = 0; swipeFired = false }
        scrollX += e.scrollingDeltaX
        scrollY += e.scrollingDeltaY
        guard !swipeFired else { return true }
        let inv: CGFloat = e.isDirectionInvertedFromDevice ? 1 : -1
        let fx = scrollX * inv, fy = scrollY * inv
        let np = PKServices.shared.nowPlaying
        if abs(fx) > 50, abs(fx) > abs(fy) * 1.4 {
            swipeFired = true
            if model.expanded { model.switchTab(forward: fx < 0) }
            else if np.hasMedia { fx < 0 ? np.next() : np.previous() }
        } else if abs(fy) > 30, abs(fy) > abs(fx) * 1.4 {
            swipeFired = true
            if fy > 0 { model.expand() } else { model.collapse() }
        }
        return true
    }
}

/// Runs the Peaky-style island in place of Vorssaint's own when the fork's
/// switch is on: one island per screen the person lets it show on, and the
/// services its views read, which Vorssaint's island would otherwise start.
final class PKIslands {
    static let shared = PKIslands()
    private(set) var controllers: [PKNotchController] = []
    private var observers: [NSObjectProtocol] = []
    private var signature = ""
    private var syncWork: DispatchWorkItem?

    /// The switch, and the island itself turned on in Vorssaint.
    static var isOn: Bool {
        NotchSupport.isEnabled() && UserDefaults.standard.bool(forKey: DefaultsKey.forkPeakyIsland)
    }

    var running: Bool { !observers.isEmpty }

    /// Called whenever Vorssaint syncs its island with the preferences.
    func sync() {
        guard Self.isOn else { stop(); return }
        if !running { start() }
        startServices()
        rebuildIfNeeded()
    }

    private func start() {
        PKIslandMenu.start()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                        queue: .main) { [weak self] _ in self?.rebuildIfNeeded() })
        // Settings change the screens it shows on: checked after they settle.
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleSync()
        })
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.controllers.forEach { $0.setLocked(true) }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.controllers.forEach { $0.setLocked(false) }
        })
    }

    private func scheduleSync() {
        syncWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Switched off (or the island turned off): Vorssaint's own island comes back.
            if Self.isOn { self.rebuildIfNeeded() } else if self.running { self.stop(); NotchService.shared.syncWithPreferences() }
        }
        syncWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    /// What Vorssaint's island starts for its music, calendar, agents and shelf.
    private func startServices() {
        NotchMusicService.shared.start()
        NotchCalendarService.shared.syncWithPreferences()
        AgentUsageService.shared.syncWithPreferences()
        if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        _ = PKServices.shared
    }

    func stop() {
        guard running || !controllers.isEmpty else { return }
        syncWork?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0); DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        controllers.forEach { $0.tearDown() }
        controllers.removeAll()
        signature = ""
    }

    /// Screens the island shows on: every one not unticked in Settings ›
    /// Each display, each over full-screen apps unless that is unticked.
    private func wanted() -> [(NSScreen, Bool)] {
        NSScreen.screens.compactMap { screen in
            let id = screen.notchDisplayID
            guard !NotchDisplayChoices.isExcluded(id) else { return nil }
            return (screen, !NotchDisplayChoices.hidesInFullscreen(on: id))
        }
    }

    private func rebuildIfNeeded() {
        let screens = wanted()
        let next = screens.map { "\($0.0.notchDisplayID):\($0.0.frame):\($0.1)" }.joined(separator: "|")
        guard next != signature else { return }
        signature = next
        controllers.forEach { $0.tearDown() }
        controllers = screens.map { PKNotchController(screen: $0.0, overFullscreen: $0.1) }
    }
}
