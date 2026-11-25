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
/// already in place and so never offered.
struct WindowSnapAssistRequest: Equatable {
    let action: WindowLayoutAction
    let rect: NSRect
    let visibleFrame: NSRect
    let snappedWindowID: CGWindowID
    let snappedPID: pid_t
}

/// The pure parts of the picker, kept apart so tests can reach them.
enum WindowSnapAssistSupport {
    /// The windows worth offering: real windows of other apps or other
    /// windows of the same app, never the snapped window, Vorssaint's own
    /// windows or a full-screen window that lives on its own Space.
    static func candidates(_ items: [SwitcherItem], excluding snappedWindowID: CGWindowID,
                           ownPID: pid_t) -> [SwitcherItem] {
        items.filter { item in
            guard let windowID = item.windowID else { return false }
            return windowID != snappedWindowID && item.pid != ownPID && item.windowOwnerPID != ownPID
                && !item.isFullscreen
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
