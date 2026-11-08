import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TournamentWidgets: WidgetBundle {
    var body: some Widget {
        TournamentLiveActivity()
    }
}

/// Tournament mode on the Lock Screen and in the Dynamic Island: the match on
/// the field now, and how many until the team's own - in the colour of the
/// alliance they will be on, so the right plates go on before queueing.
struct TournamentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TournamentActivityAttributes.self) { context in
            LockScreenCard(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(red: 0.055, green: 0.063, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NowOnField(state: state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    UntilBlock(state: state, compact: true)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NextMatchLine(team: context.attributes.team, state: state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(state.currentLabel ?? "Q–")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } compactTrailing: {
                Group {
                    if state.isDone {
                        StrokeIcon(.check, size: 13)
                    } else if let next = state.nextLabel, let count = state.matchesUntil {
                        Text(count == 0 ? "\(next) up" : "\(count) until \(next)")
                    }
                }
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(state.allianceColour)
            } minimal: {
                Text(state.isDone ? "✓" : state.matchesUntil.map(String.init) ?? "–")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(state.allianceColour)
            }
            .keylineTint(state.allianceColour)
        }
    }
}

private struct LockScreenCard: View {
    let attributes: TournamentActivityAttributes
    let state: TournamentActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                StrokeIcon(.flag, size: 13)
                Text(attributes.team)
                    .font(.caption.weight(.bold))
                Text(attributes.eventName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isStale {
                    // Shown once the app has not refreshed for a while, so an
                    // old count is not read as the current one.
                    Text("Updated \(state.updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(alignment: .top, spacing: 12) {
                NowOnField(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1)
                UntilBlock(state: state, compact: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            NextMatchLine(team: attributes.team, state: state)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// The match being played, or the one the field is about to start.
private struct NowOnField: View {
    let state: TournamentActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.6))
            Text(state.currentLabel ?? "–")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let started = state.currentStarted {
                Text("Started \(started.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            } else if let scheduled = state.currentScheduled {
                Text("Scheduled \(scheduled.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var caption: String {
        if state.phase == "waiting" { return "FIRST MATCH" }
        return state.currentStarted != nil ? "ON THE FIELD" : "UP NEXT"
    }
}

/// How many matches until the team's own, in its alliance colour.
private struct UntilBlock: View {
    let state: TournamentActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        VStack(alignment: compact ? .trailing : .leading, spacing: 2) {
            if state.isDone {
                Text("DONE")
                    .font(.caption2.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                Text("Qualifiers complete")
                    .font(.subheadline.weight(.semibold))
            } else if let next = state.nextLabel, let count = state.matchesUntil {
                Text(count == 0 ? "YOUR MATCH" : compact ? "UNTIL \(next)" : "MATCHES UNTIL \(next)")
                    .font(.caption2.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Text(count == 0 ? next : "\(count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(state.allianceColour)
                if let side = state.sideLine {
                    Text(compact || state.allianceName == nil ? side : "\(side) · \(next)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state.allianceColour)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Where and when the team's match should start: the schedule moved by how
/// late the field is actually running, counting down while it is ahead.
private struct NextMatchLine: View {
    let team: String
    let state: TournamentActivityAttributes.ContentState

    var body: some View {
        if !state.isDone, let next = state.nextLabel {
            HStack(spacing: 6) {
                Text([next, state.nextField].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let estimate = state.nextEstimated, estimate > Date() {
                    // Counts down on its own between refreshes.
                    Text("in ") + Text(timerInterval: Date()...estimate, countsDown: true)
                        .monospacedDigit()
                } else if let time = state.nextEstimated ?? state.nextScheduled {
                    Text("Est. \(time.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}
