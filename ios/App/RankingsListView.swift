import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
struct RankingsListView: View {
    /// Pushes a team onto the tab's stack - for the podium, whose three steps
    /// share one list row, where NavigationLinks would draw three chevrons
    /// and the row could not tell which was tapped.
    var open: (TeamRef) -> Void = { _ in }
    @Environment(\.vexTheme) private var theme
    @Environment(\.program) private var program
    @State private var model = RankingsModel()
    /// Set once the list first shows, so its opening rows rise in order;
    /// rows made after that (scrolling, refiltering) are simply there.
    @State private var entered = false
    @State private var filter = RankingFilter()

    var body: some View {
        if program.isIQ { IQRankingsView() } else { v5Body }
    }

    private var v5Body: some View {
        Group {
            switch model.state {
            case .loading:
                PlaceholderList()
            case .failed(let message):
                // Says what went wrong and offers the way out, rather than an
                // empty list that reads as "no teams exist".
                ContentUnavailableView {
                    Label("Could not load rankings", icon: .offline, size: 48, relativeTo: .largeTitle, drawsOn: true)
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .tint(theme.accent)
                        .foregroundStyle(theme.onAccent)
                }
            case .loaded(let teams):
                let shown = filter.apply(to: teams)
                VStack(spacing: 0) {
                    controls(teams)
                    summary(shown)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    Divider().overlay(Color.hairline)
                    if shown.isEmpty {
                        ContentUnavailableView {
                            Label("No teams match", icon: .filter, size: 48, relativeTo: .largeTitle, drawsOn: true)
                        } description: {
                            Text("No team meets these filters.")
                        }
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

            HStack(spacing: 8) {
                menu(title: filter.country ?? "All countries",
                     icon: .globe,
                     isActive: filter.country != nil,
                     options: RankingFilter.countries(teams),
                     reset: "All countries") { country in
                    filter.country = country
                    // A region from the old country would match nothing.
                    filter.region = nil
                }

                menu(title: filter.region ?? "All regions",
                     icon: .map,
                     isActive: filter.region != nil,
                     options: RankingFilter.regions(teams, country: filter.country),
                     reset: "All regions") { filter.region = $0 }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func menu(title: String, icon: VEXIcon, isActive: Bool, options: [String], reset: String,
                      select: @escaping (String?) -> Void) -> some View {
        Menu {
            Button(reset) { Haptics.selection(); select(nil) }
            ForEach(options, id: \.self) { option in
                Button(option) { Haptics.selection(); select(option) }
            }
        } label: {
            FilterPill(title, icon: icon, isActive: isActive)
        }
        .buttonStyle(.pressable)
    }

    private func list(_ teams: [TeamRanking]) -> some View {
        // No pagination cap: List recycles rows, so all 585 cost the same as 20.
        let order = Dictionary(teams.prefix(10).enumerated().map { ($1.id, $0) }) { a, _ in a }
        let low = Double(teams.last?.rating ?? 0)
        let high = Double(teams.first?.rating ?? 1)
        // The podium belongs to the unsearched list: a search for one team
        // should show that team, not three others above it.
        let podium = filter.search.isEmpty && teams.count >= 3 ? Array(teams.prefix(3)) : []
        return List {
            if !podium.isEmpty {
                RankingPodium(teams: podium, open: open)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            }
            ForEach(teams) { team in
                NavigationLink(value: TeamRef(team.number)) {
                    row(team, level: high > low ? (Double(team.rating) - low) / (high - low) : 1)
                }
                .entrance(order[team.id] ?? 10, shown: entered)
                .listRowBackground(theme.surface)
            }
        }
        .listStyle(.plain)
        .task { entered = true }
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(force: true) }
    }

    /// The web's metric strip: how many teams the current filter leaves, how
    /// much official data is behind the table, and who leads it.
    private func summary(_ teams: [TeamRanking]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Metric("\(filter.grade == .all ? "Teams" : filter.grade.rawValue) rated",
                   "\(teams.count)",
                   detail: filter.country ?? "4+ official matches")
            Metric("Events",
                   model.meta.map { "\($0.eventsProcessed)" } ?? "…",
                   detail: model.meta.map { "\($0.matchesProcessed) matches" } ?? "")
            Metric("Top rating",
                   teams.first.map { "\($0.rating)" } ?? "—",
                   detail: teams.first?.number ?? "No qualifying teams")
        }
    }

    private func row(_ team: TeamRanking, level: Double) -> some View {
        HStack(spacing: 14) {
            Group {
                if team.rank <= 3 {
                    PlaceBadge(team.rank, size: 32)
                } else {
                    Text("#\(team.rank)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.number).font(.headline)
                Text(team.name).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1)
                if let record = team.record {
                    Text("\(record) · \(RankingFilter.regionOf(team) ?? "Unassigned")")
                        .font(.caption2).foregroundStyle(.subtle).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // The last few events' rating changes, run together: which way
            // the team is heading, where the number only says where it is.
            if let form = team.form, form.count > 1 {
                Sparkline(form.reduce(into: [0.0]) { $0.append($0.last! + Double($1.change)) }, animated: false)
                    .frame(width: 44, height: 22)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(team.rating)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                // Where the rating sits between the bottom and top of the
                // list on screen.
                LevelBar(fraction: level, colour: theme.accent, height: 4, animated: false)
                    .frame(width: 52)
                Text("±\(team.confidence)").font(.caption2).foregroundStyle(.subtle)
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
    private let api = VEXRankAPI.shared

    /// When the table last came back from the server. Coming back to the tab
    /// (from a profile, say) re-runs the screen's task, and refetching then
    /// rebuilt all 3,000 rows under the reader's thumb for a ranking that
    /// had not moved; a pull to refresh still forces it.
    @ObservationIgnored private var fetched: Date?

    @MainActor
    func load(force: Bool = false) async {
        if !force, state.isLoaded, let fetched, Date.now.timeIntervalSince(fetched) < 300 { return }
        // Draw the table the app had last time while the current one is
        // fetched. A cold launch otherwise spends its first second on a spinner
        // in front of a ranking that has barely moved since the reader last
        // looked, which is the slowest the app ever feels.
        if case .failed = state { state = .loading }
        if case .loading = state, let known = await api.lastKnownRankings() {
            meta = (known.eventsProcessed, known.matchesProcessed)
            state = .loaded(known.sortedForDisplay)
        }
        do {
            let response = try await api.rankings()
            fetched = .now
            meta = (response.eventsProcessed, response.matchesProcessed)
            // Client-side ordering: the deployed Worker sorts by
            // rating - confidence while returning rating.
            state = .loaded(response.sortedForDisplay)
        } catch {
            // Keep whatever is on screen: a snapshot that is a few hours old
            // beats replacing a working table with an error.
            if case .loaded = state { return }
            state = .failed(error.localizedDescription)
        }
    }
}

/// Rankings for VEX IQ. The rating rows appear once the server returns IQ
/// ratings; until then a card says the rating is coming, and the list is the
/// one official IQ leaderboard there is, world skills, labelled as such.
@available(iOS 17.0, *)
struct IQRankingsView: View {
    @Environment(\.vexTheme) private var theme
    @State private var model = IQRankingsModel()
    @State private var season = Program.iqSeasons[0].id
    @State private var grade = "All"
    @State private var country: String?
    @State private var query = ""
    @State private var showProvisional = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("Grade", selection: $grade) {
                    Text("All").tag("All")
                    ForEach(Program.viqrc.grades, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Menu {
                        Picker("Season", selection: Binding(get: { season }, set: { Haptics.selection(); season = $0 })) {
                            ForEach(Program.iqSeasons, id: \.id) { Text($0.label).tag($0.id) }
                        }
                    } label: {
                        FilterPill(Program.iqSeasons.first { $0.id == season }?.label ?? "Season",
                                   icon: .calendar, isActive: season != Program.iqSeasons[0].id)
                    }
                    .buttonStyle(.pressable)
                    Menu {
                        Button("All countries") { Haptics.selection(); country = nil }
                        ForEach(model.countries, id: \.self) { name in Button(name) { Haptics.selection(); country = name } }
                    } label: {
                        FilterPill(country ?? "All countries", icon: .globe, isActive: country != nil)
                    }
                    .buttonStyle(.pressable)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            Divider().overlay(Color.hairline)
            content
        }
        .animation(.easeOut(duration: 0.35), value: model.isLoaded)
        .background(theme.page)
        .searchable(text: $query, prompt: "Search team number or name")
        .task(id: season) {
            country = nil
            await model.load(season: season)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.error {
            ContentUnavailableView {
                Label("Could not load world skills", icon: .offline, size: 48, relativeTo: .largeTitle, drawsOn: true)
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.load(season: season) } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(theme.accent)
                    .foregroundStyle(theme.onAccent)
            }
        } else if !model.isLoaded {
            PlaceholderList()
        } else {
            let rows = shown
            List {
                Section {
                    if model.ratings.isEmpty {
                        comingSoon
                    } else {
                        Toggle("Include provisional teams", isOn: $showProvisional)
                            .tint(theme.accent)
                            .font(.subheadline)
                        let rated = model.ratings.filter { showProvisional || $0.provisional != true }
                        if rated.isEmpty {
                            Text("No team has enough evidence for a confirmed rating yet.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Array(rated.prefix(250).enumerated()), id: \.element.id) { index, team in
                            // The team's place in the world, not in this filtered list.
                            let worldRank = showProvisional ? team.rank : (team.confirmedRank ?? index + 1)
                            NavigationLink(value: TeamRef(team.number)) { ratingRow(worldRank, team) }
                        }
                    }
                } header: {
                    Text("VIQCR")
                } footer: {
                    if !model.ratings.isEmpty {
                        Text("\(model.modelVersion ?? "VIQCR") · a Vex-Rank model, not an official ranking. Teamwork 55%, driving and coding 17.5% each, consistency across partners 10%. Provisional teams lack two teamwork events, three partners, both skills modes or recent consistency evidence.")
                    }
                }
                .listRowBackground(theme.surface)

                Section {
                    if rows.isEmpty {
                        Text("No teams match these filters.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, team in
                        NavigationLink(value: TeamRef(team.number)) { skillsRow(index + 1, team) }
                    }
                } header: {
                    Text("World skills standings")
                } footer: {
                    Text("Official Event.VEX standings: each team's best combined driver and autonomous coding run this season.")
                }
                .listRowBackground(theme.surface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.load(season: season) }
        }
    }

    private var shown: [SkillsEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.skills.filter { team in
            (grade == "All" || team.grade == grade)
                && (country == nil || team.country == country)
                && (needle.isEmpty || team.number.lowercased().contains(needle) || team.name.lowercased().contains(needle))
        }
    }

    private var comingSoon: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(theme.accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("The VEX IQ rating is coming soon.").font(.subheadline.weight(.semibold))
                Text("It is being built for teamwork matches, where two teams share one score. Nothing here shows an estimated rating meanwhile.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func ratingRow(_ position: Int, _ team: TeamRanking) -> some View {
        HStack(spacing: 14) {
            Text("#\(position)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(team.number).font(.headline)
                    if team.provisional == true {
                        Text("PROVISIONAL").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    }
                }
                Text(team.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let parts = team.components,
                   let teamwork = parts["teamwork"], let driving = parts["driving"], let coding = parts["coding"], let consistency = parts["consistency"] {
                    Text("Teamwork \(teamwork.points) · Driving \(driving.points) · Coding \(coding.points) · Consistency \(consistency.points)")
                        .font(.caption2).foregroundStyle(.subtle).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(team.rating)").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                Text("±\(team.confidence)").font(.caption2).foregroundStyle(.subtle).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func skillsRow(_ position: Int, _ team: SkillsEntry) -> some View {
        HStack(spacing: 14) {
            Text("#\(position)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.number).font(.headline)
                Text(team.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text([team.grade, team.region].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.subtle).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(team.combinedSkills)").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                Text("\(team.driverSkills) + \(team.autoSkills)").font(.caption2).foregroundStyle(.subtle).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

@available(iOS 17.0, *)
@Observable
final class IQRankingsModel {
    private(set) var skills: [SkillsEntry] = []
    /// IQ ratings, once the server has them. Empty while the rating is pending,
    /// and empty against a server that predates VEX IQ, which would otherwise
    /// answer with V5 rows.
    private(set) var ratings: [TeamRanking] = []
    private(set) var modelVersion: String?
    private(set) var countries: [String] = []
    private(set) var isLoaded = false
    private(set) var error: String?
    private let api = VEXRankAPI.shared

    @MainActor
    func load(season: Int) async {
        error = nil
        do {
            let feed = try await api.skills(season: season)
            skills = feed.rankings
            countries = Set(feed.rankings.compactMap(\.country)).filter { !$0.isEmpty }.sorted()
            isLoaded = true
        } catch {
            if !isLoaded { self.error = error.localizedDescription }
        }
        if let response = try? await api.rankings(),
           response.program == Program.viqrc.rawValue, response.ratingStatus != "pending" {
            ratings = response.sortedForDisplay
            modelVersion = response.modelVersion
        }
    }
}

/// The top three, stood on a podium: first in the middle and highest, the
/// steps rising in when the list first appears.
@available(iOS 17.0, *)
struct RankingPodium: View {
    let teams: [TeamRanking]
    let open: (TeamRef) -> Void
    @Environment(\.vexTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            step(teams[1], place: 2, height: 64, delay: 0.1)
            step(teams[0], place: 1, height: 92, delay: 0)
            step(teams[2], place: 3, height: 46, delay: 0.2)
        }
        .padding(.top, 8)
        .onAppear {
            guard !risen else { return }
            if reduceMotion { risen = true } else { withAnimation(VEXMotion.arrive) { risen = true } }
        }
    }

    private func step(_ team: TeamRanking, place: Int, height: CGFloat, delay: Double) -> some View {
        let medal = Color.medal(place) ?? theme.accent
        // A tap gesture, not a Button or NavigationLink: three of either in
        // one list row were swallowed by the row's own tap handling.
        return VStack(spacing: 6) {
                VStack(spacing: 2) {
                    Text(team.number)
                        .font(.system(place == 1 ? .headline : .subheadline, design: .rounded, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(team.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    CountingNumber(team.rating)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(medal)
                }
                .opacity(risen ? 1 : 0)
                .animation(VEXMotion.arrive.delay(delay + 0.25), value: risen)

                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [medal.opacity(0.45), medal.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
                                .fill(medal).frame(height: 3)
                        }
                    Text("\(place)")
                        .font(.system(size: place == 1 ? 34 : 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(medal)
                        .padding(.top, 8)
                }
                .frame(height: risen ? height : 0, alignment: .top)
                .clipped()
                .animation(.spring(duration: 0.7, bounce: 0.25).delay(delay), value: risen)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92 + 64, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { Haptics.tap(); open(TeamRef(team.number)) }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(TeamRef(team.number)) }
            .accessibilityLabel("Place \(place), \(team.number) \(team.name), rating \(team.rating)")
    }
}
