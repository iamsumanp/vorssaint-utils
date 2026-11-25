// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum WindowSnapAssistTests {
    static func run(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.windowSnapAssist] as? Bool == true,
                     "Snap Assist is on by default")

        let pairs: [(WindowLayoutAction, WindowLayoutAction)] = [
            (.leftHalf, .rightHalf), (.rightHalf, .leftHalf), (.topHalf, .bottomHalf), (.bottomHalf, .topHalf),
            (.leftTwoThirds, .rightThird), (.rightTwoThirds, .leftThird),
            (.leftThird, .rightTwoThirds), (.rightThird, .leftTwoThirds),
            (.topTwoThirds, .bottomThird), (.bottomTwoThirds, .topThird),
            (.topThird, .bottomTwoThirds), (.bottomThird, .topTwoThirds),
        ]
        for (action, expected) in pairs {
            suite.expect(WindowLayoutGeometry.complement(of: action) == expected,
                         "\(action.rawValue) leaves \(expected.rawValue) to fill")
        }
        for action in [WindowLayoutAction.maximize, .center, .topLeft, .leftQuarter, .centerHalf, .centerThird,
                       .fullScreen, .restore, .nextDisplay] {
            suite.expect(WindowLayoutGeometry.complement(of: action) == nil,
                         "\(action.rawValue) leaves no single space, so Snap Assist stays closed")
        }

        // The complement tiles the display exactly with the snapped placement.
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        for (action, expected) in pairs {
            let a = WindowLayoutGeometry.rect(for: action, current: .zero, visibleFrame: visible)
            let b = WindowLayoutGeometry.rect(for: expected, current: .zero, visibleFrame: visible)
            suite.expect(!a.intersects(b) && abs(a.width * a.height + b.width * b.height - visible.width * visible.height) < 4000,
                         "\(action.rawValue) and \(expected.rawValue) share the display without overlapping")
        }

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let snapped = SwitcherItem.window(id: 10, title: "Chat", appName: "Claude", pid: 100,
                                          isOnScreen: true, frame: frame)
        let dia = SwitcherItem.window(id: 11, title: "Docs", appName: "Dia", pid: 200,
                                      isOnScreen: false, frame: frame)
        let diaTwo = SwitcherItem.window(id: 12, title: "Mail", appName: "Dia", pid: 200,
                                         isOnScreen: true, isMinimized: true, frame: frame)
        let mediator = SwitcherItem.window(id: 13, title: "Dia notes", appName: "Notes", pid: 300,
                                           isOnScreen: true, frame: frame)
        let full = SwitcherItem.window(id: 14, title: "Movie", appName: "TV", pid: 400,
                                       isOnScreen: false, isFullscreen: true, frame: frame)
        let own = SwitcherItem.window(id: 15, title: "Settings", appName: "Vorssaint", pid: 1,
                                      isOnScreen: true, frame: frame)
        let app = SwitcherItem.appOnly(appName: "Finder", pid: 500)
        let candidates = WindowSnapAssistSupport.candidates([snapped, dia, diaTwo, mediator, full, own, app],
                                                            excluding: 10, ownPID: 1)
        suite.expect(candidates.map(\.windowID) == [11, 12, 13],
                     "the snapped window, own windows, full-screen windows and windowless apps are never offered")

        suite.expect(WindowSnapAssistSupport.filter(candidates, query: "").map(\.windowID) == [11, 12, 13],
                     "with nothing typed the list keeps its most-recently-used order")
        suite.expect(WindowSnapAssistSupport.filter([mediator, dia, diaTwo], query: "di").map(\.windowID) == [11, 12, 13],
                     "an app whose name starts with the letters comes before a title that only contains them")
        suite.expect(WindowSnapAssistSupport.filter(candidates, query: "MAIL").map(\.windowID) == [12],
                     "typing matches window titles regardless of case")
        suite.expect(WindowSnapAssistSupport.filter(candidates, query: "zzz").isEmpty,
                     "letters that match nothing leave the list empty")

        suite.expect(WindowSnapAssistSupport.columns(width: 960, card: 208, spacing: 14, padding: 34) == 4,
                     "a half of a 1920-point display fits four cards across")
        suite.expect(WindowSnapAssistSupport.columns(width: 200, card: 208, spacing: 14, padding: 34) == 1,
                     "a narrow space still shows one column")

        suite.expect(WindowSnapAssistSupport.move(0, keyCode: kVK_RightArrow, columns: 4, count: 6) == 1,
                     "right moves to the next card")
        suite.expect(WindowSnapAssistSupport.move(1, keyCode: kVK_DownArrow, columns: 4, count: 6) == 5,
                     "down moves one row")
        suite.expect(WindowSnapAssistSupport.move(3, keyCode: kVK_DownArrow, columns: 4, count: 6) == 5,
                     "down past the last card stops on it")
        suite.expect(WindowSnapAssistSupport.move(0, keyCode: kVK_LeftArrow, columns: 4, count: 6) == 0,
                     "left from the first card stays put")
        suite.expect(WindowSnapAssistSupport.move(0, keyCode: kVK_UpArrow, columns: 4, count: 0) == 0,
                     "an empty list keeps the selection at zero")
    }
}
