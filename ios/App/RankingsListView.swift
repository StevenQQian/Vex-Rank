import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
struct RankingsListView: View {
    @Environment(\.vexTheme) private var theme
    @State private var model = RankingsModel()
    @State private var query = ""

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
                let shown = filter(teams)
                if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    list(shown)
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.state.isLoaded)
        .background(theme.page)
        .searchable(text: $query, prompt: "Search team number or name")
        .task { await model.load() }
    }

    private func filter(_ teams: [TeamRanking]) -> [TeamRanking] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return teams }
        return teams.filter {
            $0.number.localizedCaseInsensitiveContains(trimmed)
            || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func list(_ teams: [TeamRanking]) -> some View {
        // No pagination cap: List recycles rows, so all 585 cost the same as 20.
        List(teams) { team in
            NavigationLink(value: team.number) {
                row(team)
            }
            .listRowBackground(theme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
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
    private let api = VEXRankAPI()

    @MainActor
    func load() async {
        state = .loading
        do {
            let response = try await api.rankings()
            // Client-side ordering: the deployed Worker sorts by
            // rating - confidence while returning rating.
            state = .loaded(response.sortedForDisplay)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
