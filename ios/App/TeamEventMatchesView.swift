import SwiftUI
import VEXRankKit

/// One team's matches at one event: what they have played and what they have
/// left, from their side of the field.
@available(iOS 17.0, *)
struct TeamEventMatchesView: View {
    let ref: TeamEventRef
    @Environment(\.vexTheme) private var theme
    @State private var model = TeamEventMatchesModel()

    var body: some View {
        List {
            if let record = model.record {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        // Where they stand, before what they played.
                        if let standing = model.standing {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("#\(standing.rank)")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(theme.accent)
                                    .monospacedDigit()
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("QUALIFICATION RANK")
                                        .font(.caption2.weight(.semibold)).tracking(1.2)
                                        .foregroundStyle(.secondary)
                                    Text(standing.division).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(standing.record)
                                        .font(.system(.title3, design: .rounded, weight: .semibold))
                                        .monospacedDigit()
                                    Text(record.remaining == 0
                                         ? "Schedule complete"
                                         : "\(record.remaining) still to play")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }

                            Divider().overlay(Color.white.opacity(0.14))

                            HStack(spacing: 14) {
                                stat("WP", standing.wp.map(String.init))
                                stat("AP", standing.ap.map(String.init))
                                stat("SP", standing.sp.map(String.init))
                                stat("High", standing.highScore.map(String.init))
                            }
                            if let s = standing.stats {
                                HStack(spacing: 14) {
                                    stat("OPR", String(format: "%.1f", s.opr))
                                    stat("DPR", String(format: "%.1f", s.dpr))
                                    stat("CCWM", String(format: "%.1f", s.ccwm))
                                }
                            }
                        } else {
                            // Registered but not seeded yet.
                            HStack(alignment: .top, spacing: 14) {
                                metric("Record", record.summary, "\(record.played) played")
                                metric("Remaining", "\(record.remaining)",
                                       record.remaining == 0 ? "Schedule complete" : "Still to play")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(theme.surface)
            }

            if !model.momentum.isEmpty {
                Section("Tournament momentum") {
                    VStack(alignment: .leading, spacing: 8) {
                        MomentumChart(points: model.momentum, accent: theme.accent)
                            .frame(height: 190)
                        let final = model.momentum.last?.cumulative ?? 0
                        Text(final == 0
                             ? "Level on points across \(model.momentum.count) matches."
                             : "\(final > 0 ? "+" : "")\(final) points across \(model.momentum.count) matches.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(theme.surface)
            }

            if !model.played.isEmpty {
                Section("Played") {
                    ForEach(model.played) { row($0) }
                }
                .listRowBackground(theme.surface)
            }

            if !model.upcoming.isEmpty {
                Section("Scheduled") {
                    ForEach(model.upcoming) { row($0) }
                }
                .listRowBackground(theme.surface)
            }

            if model.record == nil, let message = model.error {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load(ref, force: true) } }
                        .tint(theme.accent)
                }
                .listRowBackground(theme.surface)
            } else if model.record == nil {
                Section { ProgressView() }.listRowBackground(theme.surface)
            } else if model.played.isEmpty && model.upcoming.isEmpty {
                Section {
                    Text("No matches are listed for \(ref.team) at this event.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(ref, force: true) }
        .background(theme.page)
        .navigationTitle("\(ref.team) · matches")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(ref)
            while !Task.isCancelled && (model.record?.remaining ?? 0) > 0 {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                await model.load(ref, force: true)
            }
        }
    }

    @ViewBuilder
    private func stat(_ label: String, _ value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ match: TeamMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(match.name).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                if match.isPlayed {
                    Text(outcomeLabel(match.outcome))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(outcomeColour(match.outcome))
                } else if let time = match.scheduled {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Text(match.colour == "red" ? "RED" : "BLUE")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(match.colour == "red" ? Color.red : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                if match.isPlayed, let mine = match.scoreFor, let theirs = match.scoreAgainst {
                    // Their score first: the whole screen is from their side.
                    Text("\(mine) – \(theirs)")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .monospacedDigit()
                }

                if let field = match.field, !field.isEmpty {
                    Text(field).font(.caption).foregroundStyle(.tertiary)
                }
            }

            if !match.partners.isEmpty {
                Text("with \(match.partners.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !match.opponents.isEmpty {
                Text("vs \(match.opponents.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.primary.opacity(0.8))
            }
        }
        .padding(.vertical, 2)
    }

    private func outcomeLabel(_ outcome: TeamMatch.Outcome) -> String {
        switch outcome {
        case .won: return "WON"
        case .lost: return "LOST"
        case .tied: return "TIED"
        case .scheduled: return ""
        }
    }

    private func outcomeColour(_ outcome: TeamMatch.Outcome) -> Color {
        switch outcome {
        case .won: return .green
        case .lost: return .red
        default: return .secondary
        }
    }
}

@available(iOS 17.0, *)
@Observable
final class TeamEventMatchesModel {
    private(set) var played: [TeamMatch] = []
    private(set) var upcoming: [TeamMatch] = []
    private(set) var record: TeamEventRecord?
    private(set) var standing: EventStanding?
    private(set) var momentum: [MomentumPoint] = []
    private(set) var error: String?
    private let api = VEXRankAPI()

    @MainActor
    func load(_ ref: TeamEventRef, force: Bool = false) async {
        if record != nil && !force { return }
        error = nil
        do {
            let detail = try await api.eventDetail(id: ref.event.id, fresh: force)
            let all = detail.matches(for: ref.team)
            played = all.filter(\.isPlayed)
            upcoming = all.filter { !$0.isPlayed }
            record = TeamEventRecord(matches: all)
            standing = detail.standing(for: ref.team)
            momentum = TeamMomentum.points(from: all)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
