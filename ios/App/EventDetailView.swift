import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
struct EventDetailView: View {
    let event: EventRef
    @Environment(\.vexTheme) private var theme
    @State private var model = EventDetailModel()
    /// Sections that the reader has asked to see in full. Without a cap, a
    /// 41-team division pushed the awards - the headline of a played event -
    /// three screens down.
    @State private var expanded: Set<String> = []

    private static let previewRows = 10

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.name).font(.headline)
                    if let day = event.day {
                        Label(day.formatted(date: .long, time: .omitted), systemImage: "calendar")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    let venue = model.detail?.event.venueLine ?? event.place
                    if !venue.isEmpty {
                        Label(venue, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(theme.surface)

            if let detail = model.detail {
                ForEach(detail.divisions) { division in
                    if !division.rankings.isEmpty {
                        let all = division.rankings.sorted { $0.rank < $1.rank }
                        let key = "division-\(division.id)"
                        Section("\(division.name) · qualification") {
                            ForEach(visible(all, key: key)) { row in
                                // The whole row is the link, so the disclosure
                                // sits at the trailing edge instead of landing
                                // between the number and the record.
                                NavigationLink(value: row.team.name) {
                                    HStack {
                                        Text("#\(row.rank)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(theme.accent)
                                            .frame(width: 44, alignment: .leading)
                                            .monospacedDigit()
                                        // The API carries the number in `name`.
                                        Text(row.team.name).font(.subheadline)
                                        Spacer()
                                        Text(row.record).font(.caption).foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            revealButton(total: all.count, key: key, noun: "teams")
                        }
                        .listRowBackground(theme.surface)
                    }
                }

                if !detail.awards.isEmpty {
                    Section("Awards") {
                        ForEach(Array(detail.awards.enumerated()), id: \.offset) { _, award in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(award.title ?? "Award").font(.subheadline)
                                let winners = (award.teamWinners ?? [])
                                    .compactMap { $0.team?.name }
                                    .joined(separator: ", ")
                                if !winners.isEmpty {
                                    Text(winners).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(theme.surface)
                }

                let skills = detail.skillsLeaderboard
                if !skills.isEmpty {
                    Section("Skills") {
                        ForEach(Array(visible(skills, key: "skills").enumerated()), id: \.element.id) { index, leader in
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 44, alignment: .leading)
                                    .monospacedDigit()
                                Text(leader.number).font(.subheadline)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(leader.total)")
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    Text("\(leader.programming) auto · \(leader.driver) driver")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                        revealButton(total: skills.count, key: "skills", noun: "teams")
                    }
                    .listRowBackground(theme.surface)
                }

                ForEach(detail.divisions) { division in
                    matchSection("\(division.name) · qualification matches",
                                 division.qualification,
                                 key: "qual-\(division.id)")
                    matchSection("\(division.name) · elimination",
                                 division.elimination,
                                 key: "elim-\(division.id)")
                }

                // Registered teams. For an upcoming event this is the only
                // thing there is to show, and the screen previously said only
                // that the event had not been played.
                if !detail.teams.isEmpty {
                    let teams = detail.teams.sorted { $0.number < $1.number }
                    Section("Registered teams") {
                        ForEach(visible(teams, key: "teams")) { team in
                            NavigationLink(value: team.number) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(team.number).font(.subheadline.weight(.medium))
                                    if let name = team.name, !name.isEmpty {
                                        Text(name).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        revealButton(total: teams.count, key: "teams", noun: "teams")
                    }
                    .listRowBackground(theme.surface)
                }

                if detail.divisions.allSatisfy({ $0.rankings.isEmpty }) && detail.awards.isEmpty && skills.isEmpty
                    && detail.divisions.allSatisfy({ ($0.matches ?? []).isEmpty })
                    && detail.teams.isEmpty {
                    // Says which of the two it is, rather than showing nothing.
                    Section {
                        Text(event.isUpcoming
                             ? "This event has not been played yet."
                             : "No official results were published for this event.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .listRowBackground(theme.surface)
                }
            } else if let message = model.error {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load(id: event.id, force: true) } }
                        .tint(theme.accent)
                }
                .listRowBackground(theme.surface)
            } else {
                Section { ProgressView() }.listRowBackground(theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.page)
        // The event name, not its date: "Aug 2" in the bar told the reader
        // nothing they could not see in the card below it.
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(id: event.id) }
    }

    @ViewBuilder
    private func matchSection(_ title: String, _ matches: [DivisionMatch], key: String) -> some View {
        if !matches.isEmpty {
            Section(title) {
                ForEach(visible(matches, key: key)) { match in
                    matchRow(match)
                }
                revealButton(total: matches.count, key: key, noun: "matches")
            }
            .listRowBackground(theme.surface)
        }
    }

    private func matchRow(_ match: DivisionMatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.name ?? "Match").font(.subheadline.weight(.medium))
                Spacer()
                Text(match.isPlayed ? (match.field ?? "Final") : "Not played")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                alliance(match.red, colour: .red, won: match.winner == "red", played: match.isPlayed)
                alliance(match.blue, colour: .blue, won: match.winner == "blue", played: match.isPlayed)
            }
        }
        .padding(.vertical, 2)
    }

    private func alliance(_ alliance: MatchAlliance?, colour: Color, won: Bool, played: Bool) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(colour).frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(played ? (alliance?.score.map(String.init) ?? "—") : "—")
                    .font(.system(.title3, design: .monospaced, weight: won ? .bold : .regular))
                    .foregroundStyle(colour)
                    .monospacedDigit()
                // Plain text, not links: a NavigationLink inside a list row
                // draws its own disclosure, and four of them per match reads
                // as clutter. The standings above are the way into a team.
                ForEach(alliance?.numbers ?? [], id: \.self) { number in
                    Text(number).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visible<T>(_ rows: [T], key: String) -> [T] {
        expanded.contains(key) ? rows : Array(rows.prefix(Self.previewRows))
    }

    @ViewBuilder
    private func revealButton(total: Int, key: String, noun: String) -> some View {
        if total > Self.previewRows && !expanded.contains(key) {
            Button("Show all \(total) \(noun)") { expanded.insert(key) }
                .font(.footnote.weight(.semibold))
                .tint(theme.accent)
        }
    }
}

@available(iOS 17.0, *)
@Observable
final class EventDetailModel {
    private(set) var detail: EventDetailResponse?
    private(set) var error: String?
    private let api = VEXRankAPI()

    @MainActor
    func load(id: String, force: Bool = false) async {
        if detail != nil && !force { return }
        error = nil
        do { detail = try await api.eventDetail(id: id) }
        catch { self.error = error.localizedDescription }
    }
}
