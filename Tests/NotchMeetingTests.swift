// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Fork addition: finding a meeting's call link and when it can be joined.
enum NotchMeetingTests {
    static func run(_ suite: TestSuite) {
        let meet = NotchMeetingSupport.link(in: [nil, "", "Join with Google Meet: https://meet.google.com/abc-defg-hij."])
        suite.expect(meet?.absoluteString == "https://meet.google.com/abc-defg-hij",
                     "a Meet link in the notes is found without the full stop after it")
        let zoom = NotchMeetingSupport.link(in: ["https://us02web.zoom.us/j/81234567890?pwd=AbC123"])
        suite.expect(zoom?.absoluteString == "https://us02web.zoom.us/j/81234567890?pwd=AbC123"
                     && zoom.flatMap(NotchMeetingSupport.providerName) == "Zoom",
                     "a Zoom link keeps its passcode and names Zoom")
        let teams = NotchMeetingSupport.link(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0>"])
        suite.expect(teams?.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0",
                     "a Teams link inside angle brackets stops at the bracket")
        suite.expect(NotchMeetingSupport.link(in: ["Room 4B", "https://example.com/agenda"]) == nil,
                     "a room or an ordinary web page is not a call")
        suite.expect(NotchMeetingSupport.link(in: ["https://zoom.us/j/1", "https://meet.google.com/aaa-bbbb-ccc"])?.host == "zoom.us",
                     "the event's own URL wins over a link in its notes")

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func event(startsIn minutes: Double, lasts: Double = 30, link: Bool = true, allDay: Bool = false) -> NotchCalendarEvent {
            NotchCalendarEvent(id: "e", title: "Standup", calendar: "Work",
                               start: now.addingTimeInterval(minutes * 60),
                               end: now.addingTimeInterval((minutes + lasts) * 60), allDay: allDay, location: "",
                               meetingURL: link ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
        }
        suite.expect(NotchMeetingSupport.canJoin(event(startsIn: 10), at: now)
                     && NotchMeetingSupport.canJoin(event(startsIn: -5), at: now),
                     "a call can be joined from ten minutes before its start and while it runs")
        suite.expect(!NotchMeetingSupport.canJoin(event(startsIn: 11), at: now)
                     && !NotchMeetingSupport.canJoin(event(startsIn: -40), at: now),
                     "not earlier than ten minutes before, nor after it ends")
        suite.expect(!NotchMeetingSupport.canJoin(event(startsIn: 2, link: false), at: now)
                     && !NotchMeetingSupport.canJoin(event(startsIn: -1, allDay: true), at: now),
                     "an event without a link, or an all-day one, has nothing to join")
    }
}
