import SwiftUI
import VEXRankKit

/// The way into tournament mode, on an event a team is playing today: what
/// it does, the switch, and - once on - the same reading the Lock Screen
/// shows, so the two can be checked against each other.
@available(iOS 17.0, *)
struct TournamentModeCard: View {
    let team: String
    let event: EventRef
    let detail: EventDetailResponse
    @Environment(\.vexTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = TournamentModeController.shared
    @State private var working = false

    /// Offered only while the event is on and the team still has a qualifier
    /// to play - or while replaying one with `-tournament-clock`.
    static func isAvailable(team: String, detail: EventDetailResponse) -> Bool {
        guard TournamentClock.isReplaying || detail.isRunning() else { return false }
        guard let status = detail.tournamentStatus(for: team, now: TournamentClock.replayNow) else { return false }
        return status.phase != .done
    }

    private var isOn: Bool { controller.isFollowing(team: team, event: event.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Rewritten each time it switches on, so the change is seen.
                StrokeIcon(.flag, size: 24, relativeTo: .title3, drawsOn: true)
                    .id(isOn)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tournament mode").font(.headline)
                    Text(isOn
                         ? "Following \(team) on your Lock Screen and Dynamic Island."
                         : "Follow \(team)'s next match on your Lock Screen and Dynamic Island.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isOn, let status = controller.status {
                reading(status)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !controller.areActivitiesEnabled {
                Text("Live Activities are turned off for Makapaka Scout in Settings.")
                    .font(.caption).foregroundStyle(.subtle)
            }
            if let error = controller.error {
                Text(error).font(.caption).foregroundStyle(.subtle)
            }

            Button {
                working = true
                Task {
                    if isOn {
                        await controller.stop()
                    } else {
                        await controller.start(team: team, event: event, detail: detail)
                    }
                    working = false
                }
            } label: {
                HStack {
                    if working { ProgressView().tint(isOn ? .primary : theme.onAccent) }
                    Text(isOn ? "Exit tournament mode" : "Enter tournament mode")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? Color.primary : theme.onAccent)
                .background(isOn ? theme.surfaceRaised : theme.accent,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.pressable)
            .sensoryFeedback(trigger: isOn) { _, on in on ? .success : .impact(weight: .light) }
            .disabled(working || (!isOn && !controller.areActivitiesEnabled))
        }
        .padding(.vertical, 6)
        .animation(VEXMotion.arrive, value: isOn)
        .animation(VEXMotion.snap, value: controller.status)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.resume() }
        }
    }

    /// Now on the field, and how far off the team's match is.
    private func reading(_ status: TournamentStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Metric(status.current?.started == nil ? "Up next" : "On the field",
                   status.current?.label ?? "–",
                   detail: status.current?.started.map { "Started \($0.formatted(date: .omitted, time: .shortened))" })
                .frame(maxWidth: .infinity, alignment: .leading)
            if let next = status.next, let count = status.matchesUntil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(count == 0 ? "Your match" : "Matches until \(next.label)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(count == 0 ? next.label : "\(count)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        // Counts down by rolling the digit, not swapping it.
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(allianceText(next.alliance))
                    if let estimate = status.estimatedStart {
                        // The plate colour in V5; the teamwork partner in
                        // VEX IQ, which has no alliances.
                        let side = next.alliance?.capitalized
                            ?? (next.partners.isEmpty ? nil : "with \(next.partners.joined(separator: ", "))")
                        Text("~\(estimate.formatted(date: .omitted, time: .shortened))\(side.map { " · \($0)" } ?? "")")
                            .font(.caption2).foregroundStyle(.subtle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The Live Activity's alliance text colours, so the app and the Lock
    /// Screen show the same plate colour.
    private func allianceText(_ alliance: String?) -> Color {
        switch alliance {
        case "red": return Color(red: 1.0, green: 0.36, blue: 0.39)
        case "blue": return Color(red: 0.43, green: 0.61, blue: 1.0)
        default: return .primary
        }
    }
}
