// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Where a placement put its window, kept by the layout service so a shortcut
/// can offer the space it left free.
struct WindowSnapAssistSnap: Equatable {
    let action: WindowLayoutAction
    let visibleFrame: NSRect
    /// The placement's AppKit rect.
    let frame: NSRect
    let windowID: CGWindowID
    let pid: pid_t
}

/// The space Snap Assist fills: the placement that completes the snap, its
/// AppKit rect on the snapped window's display, and the window that is
/// already in place and so never offered. After a corner the grid fills one
/// quarter at a time: `remaining` holds the quarters still to offer and
/// `placedWindowIDs` the windows earlier steps put in place.
struct WindowSnapAssistRequest: Equatable {
    let action: WindowLayoutAction
    let rect: NSRect
    let visibleFrame: NSRect
    let snappedWindowID: CGWindowID
    let snappedPID: pid_t
    var remaining: [WindowLayoutAction] = []
    var placedWindowIDs: [CGWindowID] = []
}

/// The pure parts of the picker, kept apart so tests can reach them.
enum WindowSnapAssistSupport {
    /// The windows worth offering: real windows of other apps or other
    /// windows of the same app, never the snapped window, Vorssaint's own
    /// windows or a full-screen window that lives on its own Space. The
    /// snapped app's other windows go last: the space is almost always for a
    /// second app, and an app like Claude keeps blank helper windows that
    /// would otherwise sit at the top of the list.
    static func candidates(_ items: [SwitcherItem], excluding snappedWindowID: CGWindowID,
                           placed: [CGWindowID] = [],
                           snappedPID: pid_t = 0, ownPID: pid_t) -> [SwitcherItem] {
        let offered = items.filter { item in
            guard let windowID = item.windowID else { return false }
            return windowID != snappedWindowID && !placed.contains(windowID)
                && item.pid != ownPID && item.windowOwnerPID != ownPID
                && !item.isFullscreen
        }
        return offered.filter { $0.pid != snappedPID } + offered.filter { $0.pid == snappedPID }
    }

    /// The spaces a snap leaves to fill, in the order Snap Assist offers
    /// them. A half or a third leaves one, its complement. A corner leaves
    /// the other three quarters: the one beside it on the same row first,
    /// then the one below or above it, then the diagonal, so each pick grows
    /// the grid next to what is already there. Anything else leaves none.
    static func fillOrder(after action: WindowLayoutAction) -> [WindowLayoutAction] {
        switch action {
        case .topLeft: return [.topRight, .bottomLeft, .bottomRight]
        case .topRight: return [.topLeft, .bottomRight, .bottomLeft]
        case .bottomLeft: return [.bottomRight, .topLeft, .topRight]
        case .bottomRight: return [.bottomLeft, .topRight, .topLeft]
        default: return WindowLayoutGeometry.complement(of: action).map { [$0] } ?? []
        }
    }

    /// Typed letters narrow the list. An app whose name starts with them
    /// comes first, then a name or title that contains them, each group in
    /// the order the list already had (most recently used first).
    static func filter(_ items: [SwitcherItem], query: String) -> [SwitcherItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return items }
        let prefix = items.filter { $0.appName.lowercased().hasPrefix(needle) }
        let prefixIDs = Set(prefix.map(\.id))
        let contains = items.filter { item in
            !prefixIDs.contains(item.id)
                && (item.appName.lowercased().contains(needle) || item.title.lowercased().contains(needle))
        }
        return prefix + contains
    }

    /// How many cards fit across the space, so the arrow keys move by rows.
    static func columns(width: CGFloat, card: CGFloat, spacing: CGFloat, padding: CGFloat) -> Int {
        max(1, Int((width - padding * 2 + spacing) / (card + spacing)))
    }

    /// The selection after an arrow key, clamped to the list.
    static func move(_ selection: Int, keyCode: Int, columns: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next: Int
        switch keyCode {
        case kVK_LeftArrow: next = selection - 1
        case kVK_RightArrow: next = selection + 1
        case kVK_UpArrow: next = selection - columns
        case kVK_DownArrow: next = selection + columns
        default: next = selection
        }
        return min(max(next, 0), count - 1)
    }
}
