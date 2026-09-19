import SwiftUI
import Charts
import VEXRankKit

@available(iOS 17.0, *)
struct TeamProfileView: View {
    let ref: TeamRef
    var number: String { ref.number }
    /// Present when arriving from the list; absent on a deep link, where the
    /// profile fetch supplies everything.
    var ranking: TeamRanking?

    /// From the list when present, otherwise resolved by the model.
    private var row: TeamRanking? { ranking ?? model.resolvedRanking }
    @Environment(\.vexTheme) private var theme
    @Environment(\.favouriteTeams) private var favourites
    @State private var model = TeamProfileModel()
    /// Seeded at init rather than assigned in `.task`: the view is recreated
    /// as the profile loads, and an assignment made from the task raced that -
    /// it ran, but the body never saw it. A State initial value survives.
    @State private var season: Int? = TeamProfileView.launchSeason

    /// `-season 197` opens the profile on that season. The same hook as
    /// `-team` and `-event`: the picker cannot be driven without tapping, so
    /// this is how the season-scoped sections get verified.
    private static var launchSeason: Int? {
        guard let index = CommandLine.arguments.firstIndex(of: "-season"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return Int(CommandLine.arguments[index + 1])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                // The fade is scoped to the part that actually changes. On
                // the whole VStack it also covered the signature, and an
                // implicit animation there replaced the pen's own pending
                // stroke animations: if the profile arrived mid-write the
                // writing stopped dead and the number stayed half drawn.
                VStack(alignment: .leading, spacing: 26) {
                    if let profile = model.profile {
                        let season = season ?? profile.seasons.first?.id
                        officialLink
                        originPortal
                        upcoming
                        seasonPicker(profile)
                        seasonBand(profile, season: season).reveal()
                        let trend = profile.ratingHistory
                            .filter { season == nil || $0.seasonId == season }
                        if trend.count > 1 { chart(trend).reveal() }
                        skills(profile, season: season).reveal()
                        competitionHistory(profile, season: season).reveal()
                        awards(profile, season: season).reveal()
                    } else if let message = model.error {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ProgressView().padding(.vertical, 20)
                    }
                }
                .animation(.easeOut(duration: 0.45), value: model.profile == nil)
            }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
        // Publishes its own visible height to the reveal modifiers inside it.
        .publishesRevealViewport()
        .background(theme.page)
        .navigationTitle(number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favourites.toggle(FavouriteTeam(number: number, name: model.profile?.team.name))
                } label: {
                    Image(systemName: favourites.contains(number) ? "star.fill" : "star")
                        .foregroundStyle(theme.accent)
                }
                .accessibilityLabel(favourites.contains(number) ? "Remove from favourites" : "Add to favourites")
            }
        }
        .task {
            await model.load(ref: ref, ranking: ranking)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("V5RC TEAM PROFILE  /  \(model.profile?.team.active == true ? "ACTIVE" : "UNRATED")")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)

            // Drawn stroke by stroke, the suffix in the theme accent.
            SignedNumberView(
                text: number,
                accentFrom: number.prefix(while: \.isNumber).count,
                ink: .white,
                accent: theme.accent
            )
            .frame(height: 96)

            if let region = row?.region ?? model.profile?.team.region {
                Label(region, systemImage: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(.primary.opacity(0.85))
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((row?.name ?? model.profile?.team.name ?? "").uppercased()).font(.title3.weight(.medium))
                    if let organization = row?.organization ?? model.profile?.team.organization, !organization.isEmpty {
                        Text(organization).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let standing = ratingStanding
                VStack(alignment: .trailing, spacing: 2) {
                    Text(standing.label).font(.caption2.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(standing.value)
                        .font(.system(size: standing.rating == nil ? 26 : 40,
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if standing.label == "LIVE VCR", let confidence = row?.confidence {
                        Text("±\(confidence)").font(.caption2).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// Which season the sections below describe. The web offers the same
    /// choice; without it the profile silently mixed two seasons' events into
    /// one list.
    ///
    /// A dropdown rather than a segmented control: a long-running team has
    /// several seasons, and segments divide the width evenly between them, so
    /// "2026-27 Override" is squeezed to "2026-2..." as soon as there are more
    /// than two. A menu costs one tap and stays readable at any count.
    @ViewBuilder
    private func seasonPicker(_ profile: TeamProfileResponse) -> some View {
        let seasons = profile.seasons
        if seasons.count > 1 {
            let selected = season ?? seasons.first!.id
            Menu {
                // A check mark on the current one, so the menu says where you
                // are as well as where you can go.
                Picker("Season", selection: Binding(get: { selected }, set: { season = $0 })) {
                    ForEach(seasons) { Text($0.shortName).tag($0.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SEASON").font(.caption2.weight(.semibold)).tracking(1.6)
                            .foregroundStyle(.secondary)
                        Text(seasons.first { $0.id == selected }?.shortName ?? "—")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            // A Menu tints its whole label with the accent, which turned the
            // heading and the season name red; plain resets that, and the
            // chevron opts back in.
            .buttonStyle(.plain)
            .accessibilityLabel("Season")
        }
    }

    /// What the figure beside the team name means.
    ///
    /// It used to be labelled "LIVE VCR" unconditionally, which was wrong twice
    /// over: an unrated team got "LIVE VCR" over a bare dash, and picking an
    /// earlier season left the *current* rating standing there as if it were
    /// that season's. The live rating only belongs to the newest season.
    private var ratingStanding: (label: String, value: String, rating: Int?) {
        let profile = model.profile
        let seasons = profile?.seasons ?? []
        let selected = season ?? seasons.first?.id
        let isCurrent = selected == nil || selected == seasons.first?.id

        if isCurrent, let row {
            return ("LIVE VCR", "\(row.rating)", row.rating)
        }
        // An earlier season has no live rating, but it does have the rating it
        // finished on.
        if let selected,
           let last = profile?.ratingHistory
               .filter({ $0.seasonId == selected })
               .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
            return ("SEASON END VCR", "\(last.rating)", last.rating)
        }
        return ("RANKING STATUS", "Unrated", nil)
    }

    /// Out to the official site, for the things this app does not carry:
    /// contact details, robot photos, the team's own description.
    @ViewBuilder
    private var officialLink: some View {
        if let url = OfficialLinks.team(number) {
            Link(destination: url) {
                HStack(spacing: 10) {
                    Image(systemName: "safari").foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View \(number) on events.vex.com")
                            .font(.subheadline.weight(.medium))
                        Text("Official team page").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    /// The way back into this team's matches at the event the reader came
    /// from - the same portal the event screen offers in the other direction,
    /// so the pair of screens is symmetric however you got to them.
    @ViewBuilder
    private var originPortal: some View {
        if let event = ref.fromEvent, model.hasOriginMatches {
            NavigationLink(value: TeamEventRef(event: event, team: number)) {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Matches at this event").font(.subheadline.weight(.medium))
                        Text(event.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    /// What this team still has to play at the competition it is at right now.
    /// Nothing is drawn when they are not at one, or when their schedule is
    /// done - which is most of the time, so it must not leave a gap.
    @ViewBuilder
    private var upcoming: some View {
        if let event = model.currentEvent, !model.upcomingMatches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP NEXT").font(.caption2.weight(.semibold)).tracking(1.6)
                        .foregroundStyle(theme.accent)
                    NavigationLink(value: event.ref.focused(on: number)) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(event.name).font(.subheadline.weight(.medium)).lineLimit(2)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(model.upcomingMatches) { match in
                    VStack(alignment: .leading, spacing: 5) {
                        Divider().overlay(Color.white.opacity(0.18))
                        HStack(alignment: .firstTextBaseline) {
                            Text(match.name).font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            if let time = match.scheduled {
                                Text(time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        HStack(spacing: 6) {
                            Text(match.colour == "red" ? "RED" : "BLUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(match.colour == "red" ? Color.red : Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            if !match.partners.isEmpty {
                                Text("with \(match.partners.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let field = match.field, !field.isEmpty {
                                Text("· \(field)").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        if !match.opponents.isEmpty {
                            Text("vs \(match.opponents.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.primary.opacity(0.8))
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func seasonBand(_ profile: TeamProfileResponse, season: Int?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SEASON SUMMARY").font(.caption2.weight(.semibold)).tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Text("ON\nRECORD").font(.system(size: 34, weight: .semibold)).lineSpacing(-4)

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                let events = profile.events?.filter { season == nil || $0.seasonId == season } ?? []
                let awards = profile.awards?.filter { season == nil || $0.seasonId == season } ?? []
                metric("Status", profile.team.active ? "Active" : "Inactive",
                       season.map { profile.grade(forSeason: $0) } ?? "\(profile.team.currentSeasonEvents) current-season events")
                metric("Season events", "\(events.count)", "Official competitions")
                metric("Season awards", "\(awards.count)", "Official award records")
                metric("Seasons found", "\(profile.team.seasons)", "Complete team history")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.band)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().overlay(Color.white.opacity(0.22))
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 28, weight: .semibold))
            Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func chart(_ history: [RatingPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tournament rating movement").font(.title3.weight(.semibold))
            GrowingRatingChart(history: history, accent: theme.accent)
                .frame(height: 220)
            Text("The published ranking uses a rolling sample of the season's most recent events, so this line can run ahead of the rating in the table.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

@available(iOS 17.0, *)
extension TeamProfileView {
    private func sectionTitle(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow.uppercased()).font(.caption2.weight(.semibold)).tracking(1.6)
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    func skills(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let runs = (profile.skills ?? []).filter { season == nil || $0.seasonId == season }
        if !runs.isEmpty {
            let best = SeasonSkills(runs: runs)
            card {
                sectionTitle("Robot skills", "Season best skills scores")
                HStack(alignment: .top, spacing: 14) {
                    skillMetric("Driver", best.driver, "Highest official driver score")
                    skillMetric("Programming", best.programming, "Highest official autonomous score")
                    skillMetric("Combined", best.combined, "Best pair at one event")
                }
            }
        }
    }

    private func skillMetric(_ label: String, _ value: Int, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Color.white.opacity(0.18))
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value > 0 ? "\(value)" : "—")
                .font(.system(size: 26, weight: .semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func competitionHistory(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let events = (profile.events ?? [])
            .filter { season == nil || $0.seasonId == season }
            .sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
        if !events.isEmpty {
            card {
                sectionTitle("Competition history", "Events and qualification")
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        Divider().overlay(Color.white.opacity(0.18))
                        NavigationLink(value: event.ref.focused(on: number)) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(event.name).font(.subheadline.weight(.medium))
                                Spacer(minLength: 8)
                                if let day = event.day {
                                    Text(day.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if let place = event.location, !place.isEmpty {
                            Text(place).font(.caption).foregroundStyle(.secondary)
                        }
                        if let result = event.eliminationResult {
                            Text(result).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                        }
                        ForEach(standings(profile, eventID: event.id), id: \.self) { standing in
                            Text("Qualification #\(standing.rank) · \(standing.record)")
                                .font(.caption).foregroundStyle(.primary.opacity(0.8))
                        }
                    }
                }
            }
        }
    }

    private func standings(_ profile: TeamProfileResponse, eventID: Int) -> [TeamEventStanding] {
        (profile.rankings ?? []).filter { $0.eventId == eventID }
    }

    @ViewBuilder
    func awards(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let awards = (profile.awards ?? []).filter { season == nil || $0.seasonId == season }
        if !awards.isEmpty {
            card {
                sectionTitle("Official recognition", "Awards")
                ForEach(Array(awards.enumerated()), id: \.offset) { _, award in
                    VStack(alignment: .leading, spacing: 4) {
                        Divider().overlay(Color.white.opacity(0.18))
                        Text(award.title ?? "Award").font(.subheadline.weight(.medium))
                        if let event = award.event {
                            Text(event).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
@Observable
final class TeamProfileModel {
    private(set) var profile: TeamProfileResponse?
    /// Resolved when the view was opened by deep link rather than from the
    /// list, so the rating and record are not left blank. Deliberately taken
    /// from the ranking endpoint rather than the last point of ratingHistory:
    /// those two are computed differently and disagree, and the ranking is the
    /// published number.
    private(set) var resolvedRanking: TeamRanking?
    private(set) var error: String?
    /// The competition the team is at right now, and what they have left to
    /// play there. Both empty unless an event is actually running.
    private(set) var currentEvent: TeamEvent?
    private(set) var upcomingMatches: [TeamMatch] = []
    private(set) var hasOriginMatches = false
    private let api = VEXRankAPI()

    /// Fetched separately and allowed to fail quietly: the schedule is a bonus
    /// on top of the profile, and a profile that loaded should not report an
    /// error because an extra request did not.
    @MainActor
    private func loadUpcoming(number: String) async {
        guard let event = profile?.currentEvent() else { return }
        guard let detail = try? await api.eventDetail(id: String(event.id)) else { return }
        let matches = detail.upcomingMatches(for: number)
        guard !matches.isEmpty else { return }
        currentEvent = event
        upcomingMatches = matches
    }

    /// Whether the event the reader arrived from lists any match for this
    /// team, which decides if the way back into them is offered.
    @MainActor
    private func loadOrigin(_ ref: TeamRef) async {
        guard let event = ref.fromEvent else { return }
        guard let detail = try? await api.eventDetail(id: event.id) else { return }
        hasOriginMatches = !detail.matches(for: ref.number).isEmpty
    }

    @MainActor
    func load(ref: TeamRef, ranking: TeamRanking?) async {
        guard profile == nil else { return }
        let number = ref.number
        do { profile = try await api.teamProfile(number: number) }
        catch { self.error = error.localizedDescription }

        await loadUpcoming(number: number)
        await loadOrigin(ref)

        guard ranking == nil else { return }
        // Best effort: a team outside the published ranking simply has none.
        if let rankings = try? await api.rankings() {
            resolvedRanking = rankings.rankings.first {
                $0.number.caseInsensitiveCompare(number) == .orderedSame
            }
        }
    }
}
