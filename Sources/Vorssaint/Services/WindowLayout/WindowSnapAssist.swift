// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

final class WindowSnapAssistModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var query = ""
    @Published var selection = 0
    @Published var loading = true
    @Published var previews: [CGWindowID: CGImage] = [:]
    let request: WindowSnapAssistRequest

    init(request: WindowSnapAssistRequest) {
        self.request = request
    }

    var visible: [SwitcherItem] { WindowSnapAssistSupport.filter(items, query: query) }
}

/// Snap Assist: after a layout shortcut snaps a window, the space it left
/// free lists the other windows, and the keyboard picks the one that fills it.
final class WindowSnapAssist {
    static let shared = WindowSnapAssist()

    static let cardWidth: CGFloat = 196
    static let cardSpacing: CGFloat = 14
    static let padding: CGFloat = 22

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.windowSnapAssist) as? Bool ?? true
    }

    private var panel: WindowSnapAssistPanel?
    private var model: WindowSnapAssistModel?
    private var keyMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var previewTask: Task<Void, Never>?
    private var generation = 0

    private init() {}

    var isShowing: Bool { panel != nil }

    /// For checking the picker by eye without pressing a shortcut: launched
    /// with `open -a Vorssaint --env VORSSAINT_TEST_SNAP_ASSIST=1`, it opens on
    /// the right half of the main display a few seconds after launch, with no
    /// window moved. Never set otherwise, so it adds nothing.
    static let testLaunch: Void = {
        guard ProcessInfo.processInfo.environment["VORSSAINT_TEST_SNAP_ASSIST"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let screen = NSScreen.main else { return }
            let visible = screen.windowLayoutVisibleFrame
            let rect = WindowLayoutGeometry.rect(for: .rightHalf, current: .zero, visibleFrame: visible,
                                                 windowGap: WindowLayoutGaps.windowGap,
                                                 screenGap: WindowLayoutGaps.screenGap).integral
            shared.show(WindowSnapAssistRequest(action: .rightHalf, rect: rect, visibleFrame: visible,
                                                snappedWindowID: 0, snappedPID: 0))
        }
    }()

    func show(_ request: WindowSnapAssistRequest) {
        dispatchPrecondition(condition: .onQueue(.main))
        close()
        generation += 1
        let generation = generation
        let model = WindowSnapAssistModel(request: request)
        self.model = model

        let host = NSHostingController(rootView: WindowSnapAssistView(
            model: model,
            text: WindowSnapAssistStrings.localized(L10n.shared.language),
            columns: WindowSnapAssistSupport.columns(width: request.rect.width, card: Self.cardWidth + 12,
                                                     spacing: Self.cardSpacing, padding: Self.padding + 12),
            pick: { [weak self] item in self?.pick(item) }))
        let panel = WindowSnapAssistPanel(contentRect: request.rect,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.setFrame(request.rect, display: false)
        self.panel = panel
        installMonitors(for: panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let snapshot = WindowEnumerator.snapshot()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let all = WindowEnumerator.listWindowsForCommandBar(snapshot: snapshot)
            let items = WindowSnapAssistSupport.candidates(all, excluding: request.snappedWindowID,
                                                                   snappedPID: request.snappedPID, ownPID: ownPID)
            DispatchQueue.main.async {
                guard let self, self.generation == generation, let model = self.model else { return }
                model.items = items
                model.loading = false
                self.previewTask = WindowPreviewProvider.shared.refreshPreviews(
                    for: items, excludedAppsKey: DefaultsKey.switcherPreviewExcludedApps
                ) { [weak model] id, image in
                    model?.previews[id] = image
                }
                for item in items {
                    if let id = item.windowID, let cached = WindowPreviewProvider.shared.cachedPreview(for: id),
                       model.previews[id] == nil {
                        model.previews[id] = cached
                    }
                }
            }
        }
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        keyMonitor = nil
        globalMonitor = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        previewTask?.cancel()
        previewTask = nil
        model = nil
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        panel.close()
    }

    /// Moves the picked window into the space, then hands it the keyboard.
    /// The window is first carried to this display's Space, restored and
    /// unhidden, as a Dock Preview drop does; the placement retries for a
    /// moment because a window coming back from another desktop or the Dock
    /// is not on screen at once.
    private func pick(_ item: SwitcherItem) {
        guard let request = model?.request, let windowID = item.windowID else { return }
        close()
        let rect = request.rect
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        let origin = CGPoint(x: rect.minX, y: primaryTop - rect.maxY)
        WindowActivator.place(item, origin: origin, pointer: CGPoint(x: rect.midX, y: rect.midY))
        attemptPlacement(item, windowID: windowID, request: request, attempt: 0)
    }

    private func attemptPlacement(_ item: SwitcherItem, windowID: CGWindowID,
                                  request: WindowSnapAssistRequest, attempt: Int) {
        let placed = WindowLayoutService.shared.place(request.action, windowID: windowID,
                                                      ownerPID: item.windowOwnerPID,
                                                      visibleFrame: request.visibleFrame)
        if placed || attempt >= 12 {
            WindowActivator.activate(item, handoffSourcePID: request.snappedPID)
            WindowActivator.focusPlacedWindow(item)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.attemptPlacement(item, windowID: windowID, request: request, attempt: attempt + 1)
        }
    }

    private func installMonitors(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === panel else { return event }
            self?.handleKey(event)
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                     queue: .main) { [weak self] _ in self?.close() }))
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                           object: nil, queue: .main) { [weak self] _ in self?.close() }))
    }

    private func handleKey(_ event: NSEvent) {
        guard let model else { return }
        let keyCode = Int(event.keyCode)
        let visible = model.visible
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch keyCode {
        case kVK_Escape:
            close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if visible.indices.contains(model.selection) { pick(visible[model.selection]) }
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            let columns = WindowSnapAssistSupport.columns(width: model.request.rect.width, card: Self.cardWidth + 12,
                                                          spacing: Self.cardSpacing, padding: Self.padding + 12)
            model.selection = WindowSnapAssistSupport.move(model.selection, keyCode: keyCode,
                                                           columns: columns, count: visible.count)
        case kVK_Tab:
            guard !visible.isEmpty else { return }
            let step = event.modifierFlags.contains(.shift) ? -1 : 1
            model.selection = (model.selection + step + visible.count) % visible.count
        case kVK_Delete:
            guard !model.query.isEmpty else { return }
            model.query.removeLast()
            model.selection = 0
        default:
            // Shortcuts belong to nobody while the picker has the keyboard:
            // ⌘Q here would quit Vorssaint, not the app behind it.
            guard modifiers.isEmpty, let characters = event.characters, !characters.isEmpty else { return }
            if model.query.isEmpty, let digit = Int(characters), (1...9).contains(digit) {
                if visible.indices.contains(digit - 1) { pick(visible[digit - 1]) }
                return
            }
            let printable = characters.filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
            guard !printable.isEmpty else { return }
            model.query += printable
            model.selection = 0
        }
    }
}

/// A non-activating panel that still takes the keyboard, so typing reaches
/// the picker while the app that was just snapped stays in front.
final class WindowSnapAssistPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
}

private struct WindowSnapAssistView: View {
    @ObservedObject var model: WindowSnapAssistModel
    let text: WindowSnapAssistStrings
    let columns: Int
    let pick: (SwitcherItem) -> Void

    var body: some View {
        let visible = model.visible
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(text.prompt)
                    .font(.system(size: 17, weight: .semibold))
                if !model.query.isEmpty {
                    Text(model.query)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                }
                Spacer(minLength: 8)
                Text(text.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !model.loading && visible.isEmpty {
                Text(text.empty)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(WindowSnapAssist.cardWidth + 12),
                                                                     spacing: WindowSnapAssist.cardSpacing),
                                                 count: columns),
                                  alignment: .leading, spacing: WindowSnapAssist.cardSpacing) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                                card(item, index: index, selected: index == model.selection)
                                    .id(item.id)
                                    .onTapGesture { pick(item) }
                            }
                        }
                        .padding(4)
                    }
                    .onChange(of: model.selection) { _, selection in
                        guard visible.indices.contains(selection) else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(visible[selection].id) }
                    }
                }
            }
        }
        .padding(WindowSnapAssist.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        )
        .padding(6)
    }

    private func card(_ item: SwitcherItem, index: Int, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let id = item.windowID, let image = model.previews[id] {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else if let icon = item.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if index < 9 && model.query.isEmpty {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .frame(width: WindowSnapAssist.cardWidth, height: WindowSnapAssist.cardWidth * 0.62)
            HStack(spacing: 6) {
                if let icon = item.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !item.title.isEmpty && item.title != item.appName {
                        Text(item.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .frame(width: WindowSnapAssist.cardWidth, alignment: .leading)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title.isEmpty ? item.appName : "\(item.appName), \(item.title)")
        .accessibilityAddTraits(.isButton)
    }
}
