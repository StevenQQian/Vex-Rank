import SwiftUI
import VEXRankKit

/// The "Teams" tab: every V5RC team on record, registered or not, searchable
/// by number, name or organization.
@available(iOS 17.0, *)
struct TeamsDirectoryView: View {
    @Environment(\.vexTheme) private var theme
    @Environment(\.favouriteTeams) private var favourites
    @State private var model = TeamsDirectoryModel()
    @State private var scope: Scope = .favourites
    @State private var query = ""

    enum Scope: String, CaseIterable, Identifiable {
        case favourites = "Favourites"
        case all = "All teams"
        var id: String { rawValue }
    }
    @State private var country: String?
    @State private var region: String?
    @State private var grade: String?

    private static let grades = ["High School", "Middle School"]

    var body: some View {
        Group {
            if scope == .favourites {
                favouritesList
            } else {
                directory
            }
        }
        .animation(.easeOut(duration: 0.25), value: scope)
        .background(theme.page)
        .searchable(text: $query, prompt: scope == .favourites
                    ? "Search your teams" : "Team number, name or organization")
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
            }
            .background(theme.page)
        }
    }

    /// The reader's own teams, drawn from what is stored on the device, so it
    /// is on screen immediately - the directory takes seconds to arrive and a
    /// shortcut that waits for it is not a shortcut.
    @ViewBuilder
    private var favouritesList: some View {
        let shown = favourites.teams.filter { team in
            let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
            return needle.isEmpty
                || team.number.lowercased().contains(needle)
                || (team.name ?? "").lowercased().contains(needle)
        }
        if favourites.teams.isEmpty {
            ContentUnavailableView {
                Label("No favourite teams yet", systemImage: "star")
            } description: {
                Text("Star a team from its profile, or swipe a row in All teams, and it will be waiting here.")
            } actions: {
                Button("Browse all teams") { scope = .all }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            }
        } else if shown.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(shown) { team in
                    NavigationLink(value: TeamRef(team.number)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.number).font(.headline)
                            if let name = team.name, !name.isEmpty {
                                Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) {
                            favourites.remove(team.number)
                        } label: {
                            Label("Remove", systemImage: "star.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var directory: some View {
        Group {
            switch model.state {
            case .loading:
                // The directory is ~11MB, so this is a wait worth explaining.
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading every team on record…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load the directory", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                }
            case .loaded:
                let results = model.search(query: query,
                                           filters: .init(country: country, region: region, grade: grade))
                VStack(spacing: 0) {
                    filters(showing: results.count)
                    Divider()
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        list(results)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.state.isLoaded)
        .task { await model.load() }
    }

    private func filters(showing: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                menu(country ?? "All countries", "globe", model.countries, "All countries") {
                    country = $0
                    // A region from the previous country would match nothing.
                    region = nil
                }
                menu(region ?? "All regions", "map", model.regions(in: country), "All regions") { region = $0 }
                menu(grade ?? "All levels", "graduationcap", Self.grades, "All levels") { grade = $0 }
            }
            .font(.caption.weight(.semibold))

            // The count of what is on screen, not just the size of the feed.
            (Text(showing == model.total
                  ? "\(model.total.formatted()) teams"
                  : "\(showing.formatted()) of \(model.total.formatted()) teams")
             + Text(model.updated.map { " · updated \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                .font(.caption2).foregroundStyle(.secondary)

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func menu(_ title: String, _ icon: String, _ options: [String], _ reset: String,
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

    private func list(_ teams: [DirectoryTeam]) -> some View {
        List(teams) { team in
            NavigationLink(value: TeamRef(team.number)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(team.number).font(.headline)
                        if team.registered != true {
                            // Otherwise a long-dead team reads as current.
                            Text("INACTIVE").font(.caption2.weight(.semibold)).tracking(0.8)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let name = team.name, !name.isEmpty {
                        Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text([team.grade, team.place].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(theme.surface)
            .swipeActions {
                Button {
                    favourites.toggle(FavouriteTeam(number: team.number, name: team.name))
                } label: {
                    Label(favourites.contains(team.number) ? "Unstar" : "Star",
                          systemImage: favourites.contains(team.number) ? "star.slash" : "star")
                }
                .tint(theme.accent)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

@available(iOS 17.0, *)
@Observable
final class TeamsDirectoryModel {
    enum State {
        case loading, loaded, failed(String)
        var isLoaded: Bool { if case .loaded = self { return true }; return false }
    }

    private(set) var state: State = .loading
    private(set) var countries: [String] = []
    private(set) var total = 0
    private(set) var updated: Date?

    /// Teams paired with their lowercased search text. Built once at load:
    /// re-lowering 56,000 teams on every keystroke is the difference between a
    /// responsive field and a stuttering one.
    private var indexed: [(team: DirectoryTeam, haystack: String)] = []
    private var teams: [DirectoryTeam] = []
    private let api = VEXRankAPI()

    @MainActor
    func load() async {
        state = .loading
        do {
            let response = try await api.teamDirectory()
            teams = response.teams
            indexed = response.teams.map { ($0, TeamDirectory.haystack($0)) }
            countries = TeamDirectory.locations(response.teams).countries
            total = response.total
            updated = response.updated
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func regions(in country: String?) -> [String] {
        TeamDirectory.locations(teams, country: country).regions
    }

    func search(query: String, filters: TeamDirectory.Filters) -> [DirectoryTeam] {
        TeamDirectory.search(indexed, query: query, filters: filters)
    }
}
