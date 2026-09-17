import SwiftUI
import VEXRankKit

/// The "Stat leaders" tab: one leaderboard per category, computed on-device
/// from the rankings and skills feeds (same as the web app - the Worker has no
/// endpoint for these).
@available(iOS 17.0, *)
struct StatLeadersView: View {
    @Environment(\.vexTheme) private var theme
    @State private var model = StatLeadersModel()
    @State private var category = StatCategory.all[0]
    @State private var country: String?

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
            content
        }
        .animation(.easeOut(duration: 0.35), value: model.state.isLoaded)
        .background(theme.page)
        .task { await model.load() }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatCategory.all) { option in
                        Button {
                            category = option
                            // A country that qualifies in one feed may not exist
                            // in the other, which would silently empty the list.
                            country = nil
                        } label: {
                            Text(option.id)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(option == category ? theme.accent : theme.surface)
                                .foregroundStyle(option == category ? Color.white : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(category.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                regionMenu
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var regionMenu: some View {
        let options = model.countries(for: category)
        if !options.isEmpty {
            Menu {
                Button("All regions") { country = nil }
                ForEach(options, id: \.self) { name in
                    Button(name) { country = name }
                }
            } label: {
                Label(country ?? "All regions", systemImage: "globe")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .tint(theme.accent)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading leaderboards…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load leaderboards", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            }
        case .loaded:
            let rows = model.rank(category: category, country: country)
            if rows.isEmpty {
                ContentUnavailableView("No qualifying teams",
                                       systemImage: "chart.bar",
                                       description: Text("No team meets this category's threshold\(country.map { " in \($0)" } ?? "")."))
            } else {
                list(rows)
            }
        }
    }

    private func list(_ rows: [StatLeader]) -> some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if row.opensProfile {
                    NavigationLink(value: row.number) { cell(index: index, row: row) }
                        .listRowBackground(theme.surface)
                } else {
                    cell(index: index, row: row).listRowBackground(theme.surface)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
    }

    private func cell(index: Int, row: StatLeader) -> some View {
        HStack(spacing: 14) {
            Text("#\(index + 1)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 46, alignment: .leading)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(row.number).font(.headline)
                Text(row.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("\(row.context) · \(row.region)")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(row.formattedValue(digits: category.fractionDigits))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

@available(iOS 17.0, *)
@Observable
final class StatLeadersModel {
    enum State {
        /// Drives the fade from spinner to content; the cases themselves carry
        /// payloads that are not worth making Equatable just for this.
        var isLoaded: Bool { if case .loaded = self { return true }; return false }

        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .loading
    private var teams: [TeamRanking] = []
    private var skills: [SkillsEntry] = []
    private let api = VEXRankAPI()

    @MainActor
    func load() async {
        state = .loading
        do {
            // Both feeds are needed before anything can rank, so they are
            // fetched concurrently rather than one after the other.
            async let rankings = api.rankings()
            async let skillsFeed = api.skills()
            teams = try await rankings.rankings
            skills = try await skillsFeed.rankings
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func rank(category: StatCategory, country: String?) -> [StatLeader] {
        StatLeaders.rank(category: category, teams: teams, skills: skills, country: country)
    }

    func countries(for category: StatCategory) -> [String] {
        StatLeaders.countries(category: category, teams: teams, skills: skills)
    }
}
