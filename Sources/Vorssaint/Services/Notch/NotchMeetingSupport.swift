// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A video call's link, found in the event's URL, location or notes the way
/// Alcove finds it, so the island can join the call: from the closed island
/// shortly before it starts and while it runs, and from the agenda.
enum NotchMeetingSupport {
    /// How long before its start a meeting offers to be joined from the closed island.
    static let joinLeadTime: TimeInterval = 10 * 60

    private static let tail = #"[^\s<>"'\]\)]*"#
    /// Checked in order; the first link found wins.
    private static let providers: [(name: String, pattern: NSRegularExpression)] = [
        ("Google Meet", #"https?://meet\.google\.com/[a-z]{3,}-[a-z]{3,}-[a-z]{3,}"# + tail),
        ("Zoom", #"https?://(?:[a-z0-9-]+\.)?zoom(?:gov)?\.(?:us|com)/(?:j|my|w|s|wc/join)/"# + tail),
        ("Microsoft Teams", #"https?://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/"# + tail),
        ("Webex", #"https?://[a-z0-9-]+\.webex\.com/"# + tail),
        ("FaceTime", #"https?://facetime\.apple\.com/join"# + tail),
        ("Slack", #"https?://app\.slack\.com/huddle/"# + tail),
        ("Jitsi", #"https?://meet\.jit\.si/"# + tail),
        ("Whereby", #"https?://(?:[a-z0-9-]+\.)?whereby\.com/"# + tail),
        ("Amazon Chime", #"https?://(?:app\.)?chime\.aws/"# + tail),
    ].compactMap { name, source in
        (try? NSRegularExpression(pattern: source, options: [.caseInsensitive])).map { (name, $0) }
    }

    /// The first call link in `texts`, read in order (the event's URL, location, notes).
    static func link(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for provider in providers {
                guard let match = provider.pattern.firstMatch(in: text, range: range),
                      let found = Range(match.range, in: text) else { continue }
                // Sentence punctuation after a link in notes is not part of it.
                let trimmed = String(text[found]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                if let url = URL(string: trimmed) { return url }
            }
        }
        return nil
    }

    /// "Google Meet", "Zoom", … for a link `link(in:)` found.
    static func providerName(_ url: URL) -> String? {
        let text = url.absoluteString
        let range = NSRange(text.startIndex..., in: text)
        return providers.first { $0.pattern.firstMatch(in: text, range: range) != nil }?.name
    }

    /// From `joinLeadTime` before the start until the end, for a timed event with a link.
    static func canJoin(_ event: NotchCalendarEvent, at now: Date) -> Bool {
        guard event.meetingURL != nil, !event.allDay else { return false }
        return now < event.end && event.start.timeIntervalSince(now) <= joinLeadTime
    }

    @discardableResult
    static func join(_ event: NotchCalendarEvent) -> Bool {
        guard let url = event.meetingURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// For checking the island by eye: launched with
    /// `open -a Vorssaint --env VORSSAINT_TEST_MEETING=<minutes>`, a made-up Meet call starts
    /// that many minutes after launch (negative: already under way) and lasts 30 minutes.
    /// Never set otherwise, so it adds nothing.
    static func testMeetings(in interval: DateInterval) -> [NotchCalendarEvent] {
        guard let start = testMeetingStart, interval.intersects(DateInterval(start: start, duration: 1800)) else { return [] }
        return [NotchCalendarEvent(id: "vorssaint-test-meeting", title: "Design review", calendar: "Test",
                                   start: start, end: start.addingTimeInterval(1800), allDay: false,
                                   location: "", meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))]
    }

    private static let testMeetingStart: Date? = ProcessInfo.processInfo
        .environment["VORSSAINT_TEST_MEETING"].flatMap(Double.init)
        .map { Date().addingTimeInterval($0 * 60) }

    static func joinTitle(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Join"
        case .ptBR: return "Entrar"
        case .es: return "Unirse"
        case .sk: return "Pripojiť"
        case .de: return "Beitreten"
        case .fr: return "Rejoindre"
        case .it: return "Partecipa"
        case .ru: return "Войти"
        case .tr: return "Katıl"
        case .ja: return "参加"
        case .ko: return "참가"
        case .zhHans, .zhTW, .zhHK: return "加入"
        case .uk: return "Приєднатися"
        }
    }

    /// The width `NotchJoinPill` takes at font size 10, for sizing the island around it.
    static func joinPillWidth(_ language: AppLanguage) -> CGFloat {
        let text = (joinTitle(language) as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width
        return (text + 11 + 3 + 12).rounded(.up)
    }

    /// "Join · Google Meet", for the tooltip and VoiceOver.
    static func joinHelp(_ event: NotchCalendarEvent, language: AppLanguage) -> String {
        let title = joinTitle(language)
        guard let url = event.meetingURL, let name = providerName(url) else { return title }
        return "\(title) · \(name)"
    }
}

/// The green Join mark: in the closed island beside the countdown, and on an
/// agenda card.
struct NotchJoinPill: View {
    let title: String
    var fontSize: CGFloat = 11
    /// Dimmed while the call is not yet within the join window.
    var muted = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "video.fill").font(.system(size: fontSize - 2, weight: .semibold))
            Text(title).font(.system(size: fontSize, weight: .semibold))
        }
        .lineLimit(1).fixedSize()
        .foregroundStyle(muted ? Color.white.opacity(0.8) : Color.black)
        .padding(.horizontal, fontSize * 0.6)
        .padding(.vertical, fontSize * 0.18)
        .background(muted ? Color.white.opacity(0.14) : Color.green, in: Capsule())
        .contentShape(Capsule())
    }
}
