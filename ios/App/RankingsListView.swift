import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
struct RankingsListView: View {
    @Environment(\.vexTheme) private var theme
    @State private var model = RankingsModel()
    @State private var filter = RankingFilter()

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Loading world ranking…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                // Says what went wrong and offers the way out, rather than an
                // empty list that reads as "no teams exist".
                ContentUnavailableView {
                    Label("Could not load rankings", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                }
            case .loaded(let teams):
                let shown = filter.apply(to: teams)
                VStack(spacing: 0) {
                    controls(teams)
                    Divider()
                    summary(shown)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    Divider()
                    if shown.isEmpty {
                        ContentUnavailableView("No teams match",
                                               systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("No team meets these filters."))
                    } else {
                        list(shown)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.state.isLoaded)
        .background(theme.page)
        .searchable(text: $filter.search, prompt: "Search team number or name")
        .task { await model.load() }
    }

    private func controls(_ teams: [TeamRanking]) -> some View {
        VStack(spacing: 10) {
            Picker("Grade", selection: $filter.grade) {
                ForEach(RankingFilter.Grade.allCases, id: \.self) {
                    Text($0 == .all ? "All" : $0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                menu(title: filter.country ?? "All countries",
                     icon: "globe",
                     options: RankingFilter.countries(teams),
                     reset: "All countries") { country in
                    filter.country = country
                    // A region from the old country would match nothing.
                    filter.region = nil
                }

                menu(title: filter.region ?? "All regions",
                     icon: "map",
                     options: RankingFilter.regions(teams, country: filter.country),
                     reset: "All regions") { filter.region = $0 }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func menu(title: String, icon: String, options: [String], reset: String,
                      select: @escaping (String?) -> Void) -> some View {
        Menu {
            Button(reset) { select(nil) }
            ForEach(options, id: \.self) { option in
                Button(option) { select(option) }
            }
        } label: {
            Label(title, systemImage: icon).lineLimit(1)
        }
        .tint(theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ teams: [TeamRanking]) -> some View {
        // No pagination cap: List recycles rows, so all 585 cost the same as 20.
        List(teams) { team in
            NavigationLink(value: team.number) { row(team) }
                .listRowBackground(theme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
    }

    /// The web's metric strip: how many teams the current filter leaves, how
    /// much official data is behind the table, and who leads it.
    private func summary(_ teams: [TeamRanking]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            summaryItem("\(filter.grade == .all ? "Teams" : filter.grade.rawValue) rated",
                        "\(teams.count)",
                        filter.country ?? "4+ official matches")
            summaryItem("Events processed",
                        model.meta.map { "\($0.eventsProcessed)" } ?? "…",
                        model.meta.map { "\($0.matchesProcessed) matches" } ?? "")
            summaryItem("Rating leader",
                        teams.first.map { "\($0.rating)" } ?? "—",
                        teams.first?.number ?? "No qualifying teams")
        }
    }

    private func summaryItem(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ team: TeamRanking) -> some View {
        HStack(spacing: 14) {
            Text("#\(team.rank)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 46, alignment: .leading)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(team.number).font(.headline)
                Text(team.name).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1)
                if let record = team.record {
                    Text("\(record) · \(RankingFilter.regionOf(team) ?? "Unassigned")")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(team.rating)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text("±\(team.confidence)").font(.caption2).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

@available(iOS 17.0, *)
@Observable
final class RankingsModel {
    enum State {
        /// Drives the fade from spinner to content; the cases themselves carry
        /// payloads that are not worth making Equatable just for this.
        var isLoaded: Bool { if case .loaded = self { return true }; return false }

        case loading
        case loaded([TeamRanking])
        case failed(String)
    }

    private(set) var state: State = .loading
    /// How much official data is behind the table, for the summary strip.
    private(set) var meta: (eventsProcessed: Int, matchesProcessed: Int)?
    private let api = VEXRankAPI()

    @MainActor
    func load() async {
        state = .loading
        do {
            let response = try await api.rankings()
            meta = (response.eventsProcessed, response.matchesProcessed)
            // Client-side ordering: the deployed Worker sorts by
            // rating - confidence while returning rating.
            state = .loaded(response.sortedForDisplay)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
