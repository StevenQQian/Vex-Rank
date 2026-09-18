import SwiftUI
import VEXRankKit

/// One event. The content is organised into tabs rather than stacked, because
/// a two-division event otherwise repeats standings, a bracket and two match
/// lists per division - eight sections before the awards are even reached.
///
/// Only tabs with something in them are offered, and the division selector
/// appears only when a tab actually spans more than one division. A final-only
/// division, which some events carry to hold the cross-division match, has no
/// standings, so it is not offered under Rankings at all.
@available(iOS 17.0, *)
struct EventDetailView: View {
    let event: EventRef
    @Environment(\.vexTheme) private var theme
    @State private var model = EventDetailModel()
    @State private var tab: EventSection?
    @State private var divisionID: Int?
    /// Lists the reader has asked to see in full. Without a cap, a 41-team
    /// division pushes everything below it three screens down.
    @State private var expanded: Set<String> = []

    private static let previewRows = 10

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                let tabs = detail.availableSections
                let selected = tab ?? tabs.first
                let divisions = selected.map { detail.divisions(for: $0) } ?? []
                let division = divisions.first { $0.id == divisionID } ?? divisions.first

                controls(tabs: tabs, selected: selected, divisions: divisions, division: division)
                Divider()
                list(detail, tab: selected, division: division)
            } else {
                list(nil, tab: nil, division: nil)
            }
        }
        .background(theme.page)
        // The event name, not its date: "Aug 2" in the bar told the reader
        // nothing they could not see in the card below it.
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(id: event.id) }
    }

    // MARK: - What there is to show

    // MARK: - Controls

    private func controls(tabs: [EventSection], selected: EventSection?,
                          divisions: [Division], division: Division?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { option in
                        Button {
                            tab = option
                            // The chosen division may not exist under the new
                            // tab; let it fall back rather than showing blank.
                            divisionID = nil
                        } label: {
                            Text(option.rawValue)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(option == selected ? theme.accent : theme.surface)
                                .foregroundStyle(option == selected ? Color.white : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Only when the tab spans more than one.
            if divisions.count > 1, selected?.isPerDivision == true {
                Menu {
                    ForEach(divisions) { option in
                        Button(option.name) { divisionID = option.id }
                    }
                } label: {
                    Label(division?.name ?? "Division", systemImage: "square.split.2x1")
                        .font(.caption.weight(.semibold))
                }
                .tint(theme.accent)
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private func list(_ detail: EventDetailResponse?, tab: EventSection?, division: Division?) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.name).font(.headline)
                    if let day = event.day {
                        Label(day.formatted(date: .long, time: .omitted), systemImage: "calendar")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    let venue = detail?.event.venueLine ?? event.place
                    if !venue.isEmpty {
                        Label(venue, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(theme.surface)

            // Only when the reader arrived from a team's profile, and only when
            // that team is actually in this event's schedule.
            if let team = event.focusTeam, model.hasMatches(for: team) {
                Section {
                    NavigationLink(value: TeamEventRef(event: event, team: team)) {
                        Label("\(team)'s matches at this event", systemImage: "list.bullet.rectangle")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .listRowBackground(theme.surface)
            }

            if let detail {
                content(detail, tab: tab, division: division)
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
    }

    @ViewBuilder
    private func content(_ detail: EventDetailResponse, tab: EventSection?, division: Division?) -> some View {
        switch tab {
        case .rankings:
            if let division { standings(division) }
        case .bracket:
            if let division {
                Section("Elimination bracket") {
                    BracketView(division: division)
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }
                .listRowBackground(theme.surface)
            }
        case .matches:
            if let division {
                matchSection("Qualification", division.qualification, key: "qual-\(division.id)")
                matchSection("Elimination", division.elimination, key: "elim-\(division.id)")
            }
        case .awards:
            awards(detail)
        case .skills:
            skills(detail)
        case .teams:
            teams(detail)
        case .none:
            Section {
                Text(event.isUpcoming
                     ? "This event has not been played yet."
                     : "No official results were published for this event.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(theme.surface)
        }
    }

    private func standings(_ division: Division) -> some View {
        let all = division.rankings.sorted { $0.rank < $1.rank }
        let key = "division-\(division.id)"
        return Section("Qualification standings") {
            ForEach(visible(all, key: key)) { row in
                // The whole row is the link, so the disclosure sits at the
                // trailing edge instead of landing between the number and the
                // record.
                NavigationLink(value: TeamRef(row.team.name, fromEvent: event)) {
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

    @ViewBuilder
    private func awards(_ detail: EventDetailResponse) -> some View {
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

    @ViewBuilder
    private func skills(_ detail: EventDetailResponse) -> some View {
        let leaders = detail.skillsLeaderboard
        Section("Skills") {
            ForEach(Array(visible(leaders, key: "skills").enumerated()), id: \.element.id) { index, leader in
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
            revealButton(total: leaders.count, key: "skills", noun: "teams")
        }
        .listRowBackground(theme.surface)
    }

    @ViewBuilder
    private func teams(_ detail: EventDetailResponse) -> some View {
        let all = detail.teams.sorted { TeamNumber.precedes($0.number, $1.number) }
        Section("Registered teams") {
            ForEach(visible(all, key: "teams")) { team in
                NavigationLink(value: TeamRef(team.number, fromEvent: event)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.number).font(.subheadline.weight(.medium))
                        if let name = team.name, !name.isEmpty {
                            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            revealButton(total: all.count, key: "teams", noun: "teams")
        }
        .listRowBackground(theme.surface)
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
                // draws its own disclosure, and four of them per match reads as
                // clutter. The standings are the way into a team.
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

    /// Whether this event lists any match for `team`, which decides if the
    /// button into their matches is offered at all.
    func hasMatches(for team: String) -> Bool {
        guard let detail else { return false }
        return !detail.matches(for: team).isEmpty
    }

    @MainActor
    func load(id: String, force: Bool = false) async {
        if detail != nil && !force { return }
        error = nil
        do { detail = try await api.eventDetail(id: id) }
        catch { self.error = error.localizedDescription }
    }
}
