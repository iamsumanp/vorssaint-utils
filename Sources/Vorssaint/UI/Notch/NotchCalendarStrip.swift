// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The next timed event, or the one under way, stays readable beside the
/// camera and moves below a physical notch when the menu bar cannot spare
/// two useful wings. Paired with another activity, that activity's mark
/// takes the title's side and the event keeps its dot and clock.
struct NotchCalendarStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var usesFullRow: Bool { geometry.compactActivityUsesFooter || geometry.compactActivityWingWidth == 0 }

    var body: some View {
        // An event ending moves the countdown on, or clears it, before the
        // strip has left.
        NotchStripHold(calendar.countdown, shows: service.compactActivity == .calendar) { content($0) }
    }

    @ViewBuilder private func content(_ countdown: NotchCalendarCountdown?) -> some View {
        if let countdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let displayTitle = Self.displayTitle(countdown.event, untitled: text.untitled)
                let remaining = NotchCalendarSupport.countdownText(until: countdown.target, now: context.date)
                Group {
                    if let companion = service.compactCompanion, geometry.compactActivityWingWidth > 0 {
                        paired(countdown, companion: companion, title: displayTitle, remaining: remaining,
                               now: context.date)
                    } else if NotchMeetingSupport.showsClosedJoin(countdown.event, at: context.date) {
                        joinRow(countdown, title: displayTitle, remaining: remaining, now: context.date)
                            .frame(width: geometry.compactActivitySize.width - geometry.compactActivityHorizontalPadding * 2,
                                   height: geometry.compactActivityContentHeight)
                    } else {
                        Button { service.openCountdownEvent() } label: {
                            Group {
                                if usesFullRow {
                                    fullRow(countdown, title: displayTitle, remaining: remaining)
                                } else {
                                    wings(countdown, title: displayTitle, remaining: remaining)
                                }
                            }
                            .frame(width: geometry.compactActivitySize.width - geometry.compactActivityHorizontalPadding * 2,
                                   height: geometry.compactActivityContentHeight)
                            .contentShape(Rectangle())
                        }
                        .modifier(countdownAccessibility(countdown, title: displayTitle, now: context.date))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, geometry.compactActivityHorizontalPadding)
                .padding(.top, geometry.compactActivityTopPadding)
            }
            .accessibilityIdentifier("notch.calendarCountdown")
        }
    }

    private func countdownAccessibility(_ countdown: NotchCalendarCountdown, title: String,
                                        now: Date) -> NotchCountdownAccessibility {
        NotchCountdownAccessibility(label: "\(countdown.ongoing ? text.ongoing : text.next): \(title)",
                                    value: NotchCalendarSupport.countdownAccessibilityText(
                                        until: countdown.target, now: now, locale: l10n.language.formattingLocale()),
                                    hint: FeatureStrings.notch(l10n.language).open, help: title)
    }

    private func fullRow(_ countdown: NotchCalendarCountdown, title: String, remaining: String) -> some View {
        // The row below the camera ends in the island's deep lower corners;
        // a fixed margin left the dot and the clock on their curve.
        HStack(spacing: 6) {
            Self.dot(countdown.event)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Self.clock(remaining, ongoing: countdown.ongoing)
        }
        .padding(.horizontal, rowInset)
    }

    private var rowInset: CGFloat { max(10, geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)) }

    private func wings(_ countdown: NotchCalendarCountdown, title: String, remaining: String) -> some View {
        let inset = geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        return HStack(spacing: 0) {
            HStack(spacing: NotchCalendarSupport.stripTitleSpacing) {
                Self.dot(countdown.event)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.leading, inset)
            .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
            .clipped()
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            // As in Peaky: the time left alone, no start time beside it.
            Self.clock(remaining, ongoing: countdown.ongoing)
            .padding(.trailing, inset)
            .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
        }
    }

    /// A call that can be joined now: the title still opens the event, and the
    /// clock's side becomes the Join button.
    @ViewBuilder private func joinRow(_ countdown: NotchCalendarCountdown, title: String,
                                      remaining: String, now: Date) -> some View {
        let joinTitle = NotchMeetingSupport.joinTitle(l10n.language)
        let help = NotchMeetingSupport.joinHelp(countdown.event, language: l10n.language)
        if usesFullRow {
            HStack(spacing: 6) {
                Button { service.openCountdownEvent() } label: {
                    HStack(spacing: 6) {
                        Self.dot(countdown.event)
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Self.clock(remaining, ongoing: countdown.ongoing)
                    }
                    .contentShape(Rectangle())
                }
                .modifier(countdownAccessibility(countdown, title: title, now: now))
                Button { service.joinCountdownMeeting() } label: { NotchJoinPill(title: joinTitle, fontSize: 10) }
                    .help(help).accessibilityLabel(help)
            }
            .padding(.horizontal, rowInset)
        } else {
            let inset = geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
            HStack(spacing: 0) {
                Button { service.openCountdownEvent() } label: {
                    HStack(spacing: NotchCalendarSupport.stripTitleSpacing) {
                        Self.dot(countdown.event)
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .padding(.leading, inset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                    .clipped()
                    .frame(height: geometry.compactActivityContentHeight)
                    .contentShape(Rectangle())
                }
                .modifier(countdownAccessibility(countdown, title: title, now: now))
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Button { service.joinCountdownMeeting() } label: {
                    // The clock gives way first when the wing is short.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: NotchCalendarSupport.stripClockSpacing) {
                            Self.clock(remaining, ongoing: countdown.ongoing)
                            NotchJoinPill(title: joinTitle, fontSize: 10)
                        }
                        NotchJoinPill(title: joinTitle, fontSize: 10)
                    }
                    .padding(.trailing, inset)
                    .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                           alignment: .leading)
                    .contentShape(Rectangle())
                }
                .help(help).accessibilityLabel(help)
            }
        }
    }

    /// Both sides sit at the ends, as a timer's pair does, and each opens
    /// its own page. Below a crowded notch the row splits the same way.
    private func paired(_ countdown: NotchCalendarCountdown, companion: NotchCompactActivity, title: String,
                        remaining: String, now: Date) -> some View {
        let footer = geometry.compactActivityUsesFooter
        let markInset = NotchCompanionMark.inset(companion, geometry: geometry)
        return HStack(spacing: 0) {
            Button { service.openActivity(companion.module) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        NotchCompanionMark(companion: companion, geometry: geometry)
                    }
                }
                .padding(.leading, footer ? max(rowInset, markInset) : markInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(NotchCompanionMark.label(companion, language: l10n.language))
            .accessibilityHint(FeatureStrings.notch(l10n.language).open)
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            let joinable = NotchMeetingSupport.showsClosedJoin(countdown.event, at: now)
            Button {
                if !(joinable && service.joinCountdownMeeting()) { service.openCountdownEvent() }
            } label: {
                Group {
                    if joinable {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: NotchCalendarSupport.stripClockSpacing) {
                                Self.clockMark(countdown, remaining: remaining)
                                NotchJoinPill(title: NotchMeetingSupport.joinTitle(l10n.language), fontSize: 10)
                            }
                            NotchJoinPill(title: NotchMeetingSupport.joinTitle(l10n.language), fontSize: 10)
                        }
                    } else {
                        Self.clockMark(countdown, remaining: remaining)
                    }
                }
                    .padding(.trailing, footer ? rowInset : geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0))
                    .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                           alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .modifier(countdownAccessibility(countdown, title: title, now: now))
        }
    }

    static func displayTitle(_ event: NotchCalendarEvent, untitled: String) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? untitled : title
    }

    /// The event's dot and its clock, as the island draws them beside another activity.
    static func clockMark(_ countdown: NotchCalendarCountdown, remaining: String) -> some View {
        HStack(spacing: NotchCalendarSupport.stripClockSpacing) {
            dot(countdown.event)
            clock(remaining, ongoing: countdown.ongoing)
        }
    }

    /// The calendar's colour as a short upright bar, as Peaky marks a meeting.
    private static func dot(_ event: NotchCalendarEvent) -> some View {
        RoundedRectangle(cornerRadius: NotchCalendarSupport.stripDotWidth / 2, style: .continuous)
            .fill(event.color.color)
            .frame(width: NotchCalendarSupport.stripDotWidth, height: 12)
            .accessibilityHidden(true)
    }

    /// Time left in an event under way takes the agenda's "happening now"
    /// color, so it never reads as a wait for the next one.
    private static func clock(_ remaining: String, ongoing: Bool) -> some View {
        Text(remaining)
            .font(.system(size: 13, weight: .medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(ongoing ? Color.mint : Color.white)
            .modifier(NotchRollingDigits(value: remaining, countsDown: true, everySecond: false))
    }
}

/// One control for the event: what it is, the time left and where it leads.
private struct NotchCountdownAccessibility: ViewModifier {
    let label: String
    let value: String
    let hint: String
    let help: String

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .help(help)
    }
}
