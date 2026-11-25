// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while an agent works: its mark on one side of the
/// camera, one reading the person chose on the other. The wings are as wide
/// as the reading, and both sit at the ends, where the island shows.
struct NotchAgentStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsIndicator) private var indicator = NotchAgentIndicator.mark.rawValue

    private func working(_ live: [AgentLiveSession]) -> [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    var body: some View {
        // The last agent stopping empties the list before the strip has left.
        NotchStripHold(usage.snapshot.live, shows: !usage.snapshot.live.isEmpty) { strip(live: $0) }
    }

    @ViewBuilder private func strip(live: [AgentLiveSession]) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let working = working(live)
        let tint = working.first?.tint ?? .white
        let budget = geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2
        let iconSize = min(working.count > 1 ? 11.0 : 14.0, max(8, budget - 4))
        let textSize = NotchAgentSupport.stripTextSize(height: geometry.compactActivityContentHeight)
        let iconInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: iconSize + 4, radius: (iconSize + 4) / 2) : 0
        let textInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) : 0
        // With the pulse dot chosen, the logo rests still left of the camera
        // and each working agent's dot pulses right of it, in place of the
        // reading. The agent logo option keeps logo and reading.
        let pulses = indicator == NotchAgentIndicator.pulse.rawValue
        // Pet + spinning logo: the pet keeps its side of the camera and the
        // working logos turn on the other.
        let spins = indicator == NotchAgentIndicator.spin.rawValue
        let petOnRight = UserDefaults.standard.string(forKey: DefaultsKey.notchMascotSide) == NotchMascotSide.right.rawValue
        let petShown = spins && NotchMascotSupport.isEnabled()
        let petSize = min(20, max(10, geometry.compactActivityContentHeight - 2))
        let pet = Button { service.openActivity(.agents) } label: {
            Group {
                if petShown, geometry.compactActivityWingWidth >= 24 {
                    NotchMascotView(look: NotchMascotSupport.look(), size: petSize)
                }
            }
            .padding(petOnRight ? .trailing : .leading, iconInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: petOnRight ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        let spinning = Button { service.openActivity(.agents) } label: {
            HStack(spacing: 1) {
                if geometry.compactActivityWingWidth >= 28 {
                    ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize) }
                }
            }
            .padding(petOnRight ? .leading : .trailing, iconInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: petOnRight ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        let marks = Button { service.openActivity(.agents) } label: {
            HStack(spacing: 1) {
                if geometry.compactActivityWingWidth >= 28 {
                    ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize, working: !pulses) }
                }
            }
            .padding(.leading, iconInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .leading)
            .contentShape(Rectangle())
        }
        let dots = Button { service.openActivity(.agents) } label: {
            HStack(spacing: 1) {
                if geometry.compactActivityWingWidth >= 28 {
                    ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize) }
                }
            }
            .padding(.trailing, iconInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .trailing)
            .contentShape(Rectangle())
        }
        let readingWing = Button { service.openActivity(.agents) } label: {
            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    NotchAgentReadoutTimeline(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed) { date in
                        let text = reading(at: date, live: live)
                        Text(text)
                            .font(.system(size: textSize, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            // A reading that gains a digit, like an hour
                            // passing, needs wider wings; the service
                            // measures the same reading.
                            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                                DispatchQueue.main.async { service.refreshPresentation() }
                            }
                    }
                }
            }
            .padding(.trailing, textInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .trailing)
            .contentShape(Rectangle())
        }
        HStack(spacing: 0) {
            if spins {
                if petOnRight { spinning } else { pet }
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                if petOnRight { pet } else { spinning }
            } else {
                marks
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                if pulses { dots } else { readingWing }
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(working.map(\.displayName).joined(separator: ", "))
        .accessibilityValue(reading(at: Date(), live: live))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date, live: [AgentLiveSession]) -> String {
        var snapshot = usage.snapshot
        snapshot.live = live
        return NotchAgentSupport.stripReading(snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                              display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                              focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// Keep the original one-second cadence for time-dependent readings, but
/// install no clock at all for values updated by the observed usage snapshot.
struct NotchAgentReadoutTimeline<Content: View>: View {
    let readout: NotchAgentReadout
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if readout.advancesWithClock {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}

/// The resting island's wings: the chosen allowance, by default the one
/// closest to running out, as a ring and a number, or today's API value when
/// no allowance is known.
struct NotchAgentRestingWing: View {
    let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = usage.snapshot
        let limit = NotchAgentSupport.restingLimit(snapshot, focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
        let used = display == NotchAgentLimitDisplay.used.rawValue
        if let limit {
            let tint = agentLimitTint(limit.provider, usedFraction: limit.window.usedFraction)
            if leading {
                NotchAgentRing(value: used ? limit.window.usedFraction : limit.window.remainingFraction,
                               tint: tint, lineWidth: 2)
                    .frame(width: 11, height: 11)
            } else {
                Text(AgentFormat.percent(used ? limit.window.usedFraction : limit.window.remainingFraction))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else if let provider = AgentProvider.allCases.first(where: snapshot.seen.contains) {
            if leading {
                NotchAgentMark(provider: provider, size: 10)
            } else {
                Text(AgentFormat.cost(snapshot, for: .today))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// The working agents below the music player: their marks, names and the
/// strip's reading, in one row that opens the AI page with their stats.
struct NotchMusicAgentsRow: View {
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        let live = usage.snapshot.live
        let working = AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
        let tint = working.first?.tint ?? .white
        Button { NotchService.shared.open(.agents) } label: {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(working) { NotchAgentGlyph(provider: $0, size: 14) }
                }
                Text(working.map(\.displayName).joined(separator: ", "))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                NotchAgentReadoutTimeline(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed) { date in
                    Text(reading(at: date))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: NotchLayout.musicAgentsRowHeight,
                   maxHeight: NotchLayout.musicAgentsRowHeight)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(FeatureStrings.notchAgents(l10n.language).title)
        .accessibilityLabel(working.map(\.displayName).joined(separator: ", "))
        .accessibilityValue(reading(at: Date()))
    }

    private func reading(at now: Date) -> String {
        NotchAgentSupport.stripReading(usage.snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                       display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                       focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// The meeting about to start, below the music player as Peaky lists it: the
/// calendar's bar, the title, the minutes left and Join once the call opens.
/// The row opens the event; Join joins the call.
struct NotchMusicMeetingRow: View {
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let event = NotchService.shared.musicMeeting {
            let title = NotchCalendarStrip.displayTitle(event, untitled: FeatureStrings.notchCalendar(l10n.language).untitled)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Button { NotchService.shared.openMeetingEvent(event) } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(event.color.color)
                            .frame(width: 3, height: 13)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(Self.when(event, now: context.date, leadTime: calendar.countdownLeadTime))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // Fill the row, so the time sits at its right edge.
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: NotchLayout.musicAgentsRowHeight,
                           maxHeight: NotchLayout.musicAgentsRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    /// Minutes once the meeting is within the countdown's lead time, the
    /// start time later today, and the weekday with the time after that.
    static func when(_ event: NotchCalendarEvent, now: Date, leadTime: TimeInterval,
                     calendar: Calendar = .current, locale: Locale = .current) -> String {
        if event.start > now, event.start.timeIntervalSince(now) <= leadTime {
            return NotchCalendarSupport.countdownText(until: event.start, now: now)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(event.start, inSameDayAs: now) ? "jmm" : "EEEjmm")
        return formatter.string(from: event.start)
    }
}
