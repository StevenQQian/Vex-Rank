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

    /// Where the team is from, in as much detail as any feed carries.
    ///
    /// The two feeds disagree about what "region" means. The teams endpoint
    /// gives "Canterbury, Victoria, Australia"; the rankings feed gives
    /// "Victoria, Australia", because it is built for a table column that has
    /// no room for a city. Reading the ranking first meant a team lost its
    /// city precisely when it was ranked, and kept it when it was not.
    ///
    /// Whichever names more places wins, the profile breaking ties, so this
    /// cannot get worse if a feed changes shape again.
    private var location: String? {
        TeamLocation.best(of: [model.profile?.team.region, row?.region])
    }
    @Environment(\.vexTheme) private var theme
    @Environment(\.favouriteTeams) private var favourites
    @Environment(\.appConfig) private var appConfig
    @Environment(\.numberFont) private var numberFont
    @Environment(\.program) private var program
    @State private var model = TeamProfileModel()
    /// Seeded at init rather than assigned in `.task`: the view is recreated
    /// as the profile loads, and an assignment made from the task raced that -
    /// it ran, but the body never saw it. A State initial value survives.
    @State private var season: Int? = TeamProfileView.launchSeason
    /// The trophy tiles rise in order the first time they are scrolled to.
    @State private var awardsShown = false

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
            VStack(alignment: .leading, spacing: 20) {
                header
                    // Bled past the screen's padding and up under the bar, so
                    // the glow reads as the page's light, not a box.
                    .background(FieldBackdrop(accent: theme.accent)
                        .padding(.horizontal, -20).padding(.top, -160).padding(.bottom, -40))
                // The fade is scoped to the part that actually changes. On
                // the whole VStack it also covered the signature, and an
                // implicit animation there replaced the pen's own pending
                // stroke animations: if the profile arrived mid-write the
                // writing stopped dead and the number stayed half drawn.
                VStack(alignment: .leading, spacing: 16) {
                    if let profile = model.profile {
                        let season = season ?? profile.seasons.first?.id
                        originPortal
                        upcoming
                        seasonPicker(profile)
                        if let season, !profile.hasLoaded(season: season) {
                            // Its rows are on their way. Drawn before they
                            // land, the history would read "no elimination
                            // result" for every event of a season that has one.
                            seasonLoading(season)
                        } else {
                            seasonBand(profile, season: season).reveal()
                            let trend = profile.ratingHistory
                                .filter { season == nil || $0.seasonId == season }
                            if program.isIQ && profile.ratingStatus == "pending" {
                                ratingComingSoon.reveal()
                            } else if trend.count > 1 { chart(trend).reveal() }
                            skills(profile, season: season).reveal()
                            competitionHistory(profile, season: season).reveal()
                            awards(profile, season: season).reveal()
                        }
                        // Last: it leaves the app, and it is the same for
                        // every team, so it should not sit above their record.
                        officialLink
                    } else if let message = model.error {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                            Button("Retry") { Task { await model.retry(ref: ref, ranking: ranking, program: program) } }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .tint(theme.accent)
                                .foregroundStyle(theme.onAccent)
                        }
                    } else {
                        ProfilePlaceholder()
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
                    // An image rather than a drawn view: the toolbar hosts its
                    // items in UIKit and does not redraw a custom view inside
                    // one. The swap is given a small overshoot instead, so
                    // starring is still the moment.
                    (favourites.contains(number) ? VEXIcon.starFilled : .star).image(size: 22)
                        .foregroundStyle(theme.accent)
                        .phaseAnimator([1.0, 1.3, 1.0], trigger: favourites.contains(number)) { star, scale in
                            star.scaleEffect(scale)
                        } animation: { _ in VEXMotion.press }
                }
                .accessibilityLabel(favourites.contains(number) ? "Remove from favourites" : "Add to favourites")
                .sensoryFeedback(trigger: favourites.contains(number)) { _, starred in
                    starred ? .success : .selection
                }
            }
        }
        .task {
            await model.load(ref: ref, ranking: ranking, program: program)
        }
        // The season on screen, whichever way it was chosen - the picker, the
        // launch argument, or the default of the newest season the team
        // played, which need not be the one loaded first.
        // Keyed on the profile's arrival too: a season chosen before there is
        // a profile to merge into (by launch argument, or a picker restored
        // too early) would otherwise be asked for once, turned away, and never
        // asked for again - leaving a spinner that does not end.
        .task(id: "\(visibleSeason ?? 0)-\(model.profile != nil)") {
            if let visibleSeason { await model.ensure(season: visibleSeason, number: number) }
        }
    }

    private var visibleSeason: Int? { season ?? model.profile?.seasons.first?.id }

    @ViewBuilder
    private func seasonLoading(_ season: Int) -> some View {
        if let message = model.seasonError[season] {
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { Task { await model.ensure(season: season, number: number) } }
                    .buttonStyle(.bordered).controlSize(.large)
                    .tint(theme.accent)
            }
        } else {
            ProfilePlaceholder()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(program.rawValue) TEAM PROFILE  /  \(model.profile?.team.active == true ? "ACTIVE" : program.isRated ? "UNRATED" : "INACTIVE")")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)

            // Drawn stroke by stroke, the suffix in the theme accent.
            SignedNumberView(
                text: number,
                font: numberFont,
                accentFrom: number.prefix(while: \.isNumber).count,
                ink: .white,
                accent: theme.accent
            )
            .frame(height: 96)
            // Re-identified on the font, so choosing one rewrites the number in
            // it there and then rather than leaving the old hand on screen
            // until the next time the profile is opened.
            .id(numberFont.id)

            Divider().overlay(Color.hairline)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row?.name ?? model.profile?.team.name ?? "").font(.title3.weight(.semibold))
                    if let organization = row?.organization ?? model.profile?.team.organization, !organization.isEmpty {
                        Text(organization).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let region = location {
                        Label(region, icon: .pin, size: 14, relativeTo: .footnote)
                            .font(.footnote)
                            .foregroundStyle(.subtle)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Spacer()
                let standing = ratingStanding
                VStack(alignment: .trailing, spacing: 2) {
                    Text(standing.label).font(.caption2.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Group {
                        if let rating = standing.rating { CountingNumber(rating) } else { Text(standing.value) }
                    }
                        .font(.system(size: standing.rating == nil ? (program.isIQ ? 20 : 26) : 40,
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if standing.label == "LIVE VCR", let confidence = row?.confidence {
                        Text("±\(confidence)").font(.caption2).foregroundStyle(.subtle)
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
                Picker("Season", selection: Binding(get: { selected }, set: { Haptics.selection(); season = $0 })) {
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
                    StrokeIcon(.chevronUpDown, size: 15, relativeTo: .footnote)
                        .foregroundStyle(theme.accent)
                }
                .vexCard(padding: 14)
                .contentShape(Rectangle())
            }
            // A Menu tints its whole label with the accent, which turned the
            // heading and the season name red; a custom style resets that,
            // the chevron opts back in, and the card sinks under the finger.
            .buttonStyle(.pressable)
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
            return (program.isIQ ? "VIQCR" : "LIVE VCR", "\(row.rating)", row.rating)
        }
        if program.isIQ {
            // A season with nothing published yet: say so, rather than
            // "Unrated", which reads as a verdict on the team.
            if profile?.ratingStatus == "pending" { return ("VEX IQ RATING", "Coming soon", nil) }
            // Otherwise the rating after the team's latest rated event.
            if let last = profile?.ratingHistory
                .filter({ selected == nil || $0.seasonId == selected })
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
                return ("VIQCR", "\(last.rating)", last.rating)
            }
            return ("VIQCR", "Unrated", nil)
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
        if let url = OfficialLinks.team(number, program: program.rawValue) {
            Link(destination: url) {
                HStack(spacing: 10) {
                    StrokeIcon(.compass, size: 20).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View \(number) on events.vex.com")
                            .font(.subheadline.weight(.medium))
                        Text("Official team page").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    StrokeIcon(.external, size: 13, relativeTo: .caption).foregroundStyle(.subtle)
                }
                .vexCard(padding: 14)
            }
            .buttonStyle(.pressable)
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
                    StrokeIcon(.list, size: 20)
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Matches at this event").font(.subheadline.weight(.medium))
                        Text(event.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    StrokeIcon(.chevronRight, size: 13, relativeTo: .caption).foregroundStyle(.subtle)
                }
                .vexCard(padding: 14)
            }
            .buttonStyle(.pressable)
        }
    }

    /// What this team still has to play at the competition it is at right now.
    /// Nothing is drawn when they are not at one, or when their schedule is
    /// done - which is most of the time, so it must not leave a gap.
    @ViewBuilder
    private var upcoming: some View {
        if let event = model.currentEvent, !model.upcomingIQ.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP NEXT").font(.caption2.weight(.semibold)).tracking(1.6)
                        .foregroundStyle(theme.accent)
                    NavigationLink(value: event.ref.focused(on: number)) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(event.name).font(.subheadline.weight(.medium)).lineLimit(2)
                            StrokeIcon(.chevronRight, size: 11, relativeTo: .caption2).foregroundStyle(.subtle)
                        }
                        // One line of text is a 20pt target; the event name
                        // is the way in, so it gets a thumb's worth.
                        .hitArea(vertical: 12)
                    }
                    .buttonStyle(.pressable)
                }
                // Teamwork: who they play with. No colour and no opponent.
                ForEach(model.upcomingIQ) { match in
                    VStack(alignment: .leading, spacing: 5) {
                        Divider().overlay(Color.hairline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(match.name).font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            if let time = match.scheduled {
                                Text(time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        if !match.partners.isEmpty {
                            Text("With \(match.partners.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .vexCard()
            // The one outlined card: while an event runs, this is the reason
            // the profile was opened.
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.5), lineWidth: 1))
        } else if let event = model.currentEvent, !model.upcomingMatches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP NEXT").font(.caption2.weight(.semibold)).tracking(1.6)
                        .foregroundStyle(theme.accent)
                    NavigationLink(value: event.ref.focused(on: number)) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(event.name).font(.subheadline.weight(.medium)).lineLimit(2)
                            StrokeIcon(.chevronRight, size: 11, relativeTo: .caption2).foregroundStyle(.subtle)
                        }
                        // One line of text is a 20pt target; the event name
                        // is the way in, so it gets a thumb's worth.
                        .hitArea(vertical: 12)
                    }
                    .buttonStyle(.pressable)
                }

                ForEach(model.upcomingMatches) { match in
                    VStack(alignment: .leading, spacing: 5) {
                        Divider().overlay(Color.hairline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(match.name).font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            if let time = match.scheduled {
                                Text(time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        HStack(spacing: 6) {
                            AllianceTag(isRed: match.colour == "red")
                            if !match.partners.isEmpty {
                                Text("with \(match.partners.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let field = match.field, !field.isEmpty {
                                Text("· \(field)").font(.caption).foregroundStyle(.subtle)
                            }
                        }
                        if !match.opponents.isEmpty {
                            Text("vs \(match.opponents.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .vexCard()
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.5), lineWidth: 1))
        }
    }

    /// The season as a picture first: how often they won, the shape of the
    /// record, and the figures that say how far they got.
    private func seasonBand(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let events = profile.events?.filter { season == nil || $0.seasonId == season } ?? []
        let awards = profile.awards?.filter { season == nil || $0.seasonId == season } ?? []
        let standings = (profile.rankings ?? []).filter { season == nil || $0.seasonId == season }
        let wins = standings.reduce(0) { $0 + $1.wins }
        let losses = standings.reduce(0) { $0 + $1.losses }
        let ties = standings.reduce(0) { $0 + $1.ties }
        let played = wins + losses + ties
        let bestRank = standings.map(\.rank).min()
        let highScore = standings.compactMap(\.highScore).max()
        let titles = events.filter { $0.eliminationResult?.localizedCaseInsensitiveContains("champion") == true
            || $0.eliminationResult?.localizedCaseInsensitiveContains("winner") == true }.count

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Season at a glance")
                Spacer()
                Text(profile.team.active ? "ACTIVE" : "INACTIVE")
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .foregroundStyle(profile.team.active ? Color.win : .secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((profile.team.active ? Color.win : .white).opacity(0.12), in: Capsule())
            }

            // Teamwork matches in VEX IQ are shared, so there is no record to
            // draw - the ring is for V5's won/lost.
            if !program.isIQ, played > 0 {
                HStack(spacing: 18) {
                    RingGauge(fraction: Double(wins) / Double(played), colour: .win, lineWidth: 11) {
                        VStack(spacing: 0) {
                            CountingNumber(Int((Double(wins) / Double(played) * 100).rounded()), suffix: "%")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("WIN RATE").font(.system(size: 9, weight: .semibold)).tracking(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 112, height: 112)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            recordFigure(wins, "W", .win)
                            recordFigure(losses, "L", .loss)
                            recordFigure(ties, "T", .secondary)
                        }
                        RecordBar(wins: wins, losses: losses, ties: ties, height: 10)
                        Text("\(played) qualification matches across \(standings.count) events")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                tile(.calendar, "Events", events.count, detail: season.map { profile.grade(forSeason: $0) } ?? "This season")
                tile(.trophy, "Awards", awards.count, detail: titles > 0 ? "\(titles) tournament win\(titles == 1 ? "" : "s")" : "Official records",
                     colour: awards.isEmpty ? nil : .gold)
                if let bestRank {
                    tile(.podium, "Best qualifying", bestRank, prefix: "#", detail: "Highest seed", colour: Color.medal(bestRank))
                } else {
                    tile(.team, "Seasons", profile.team.seasons, detail: "Team history")
                }
                if let highScore {
                    tile(.stats, "High score", highScore, detail: "One match")
                } else {
                    tile(.team, "Seasons", profile.team.seasons, detail: "Team history")
                }
            }
        }
        .vexCard()
    }

    private func recordFigure(_ value: Int, _ label: String, _ colour: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            CountingNumber(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption.weight(.bold)).foregroundStyle(colour)
        }
    }

    private func tile(_ icon: VEXIcon, _ label: String, _ value: Int, prefix: String = "",
                      detail: String, colour: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StrokeIcon(icon, size: 14, relativeTo: .caption)
                    .foregroundStyle(colour ?? theme.accent)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            CountingNumber(value, prefix: prefix)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(colour ?? .primary)
            Text(detail).font(.caption2).foregroundStyle(.subtle).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Where the rating line will go, in the same place and style.
    private var ratingComingSoon: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Rating movement")
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(theme.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The VEX IQ rating is coming soon.").font(.subheadline.weight(.semibold))
                    Text("It is being built for teamwork matches, where two teams share one score. Nothing here shows an estimated rating meanwhile.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .vexCard()
    }

    private func chart(_ history: [RatingPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Rating movement", detail: "After each tournament")
                Spacer()
                let net = history.reduce(0) { $0 + $1.change }
                Text("\(net >= 0 ? "+" : "")\(net)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(net >= 0 ? Color.win : Color.loss)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background((net >= 0 ? Color.win : Color.loss).opacity(0.14), in: Capsule())
                    .accessibilityLabel("\(net >= 0 ? "Up" : "Down") \(abs(net)) this season")
            }
            GrowingRatingChart(history: history, accent: theme.accent)
                .frame(height: 200)
            Text("The published ranking uses a rolling sample of the season's most recent events, so this line can run ahead of the rating in the table.")
                .font(.caption2).foregroundStyle(.subtle)
        }
        .vexCard()
    }
}

@available(iOS 17.0, *)
extension TeamProfileView {
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).vexCard()
    }

    @ViewBuilder
    func skills(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let runs = (profile.skills ?? []).filter { season == nil || $0.seasonId == season }
        if !runs.isEmpty {
            let best = SeasonSkills(runs: runs)
            let scale = Double(max(best.driver, best.programming, 1))
            card {
                HStack(alignment: .top) {
                    SectionHeader("Skills", detail: "Season best official scores")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        CountingNumber(best.combined)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                        Text("COMBINED").font(.system(size: 9, weight: .semibold)).tracking(1)
                            .foregroundStyle(.secondary)
                    }
                }
                skillBar(.robot, "Driver", best.driver, fraction: Double(best.driver) / scale, delay: 0)
                skillBar(.settings, program.isIQ ? "Coding" : "Auton", best.programming,
                         fraction: Double(best.programming) / scale, delay: 0.12)
                Text("Combined is the best driver and \(program.isIQ ? "coding" : "auton") pair from one event.")
                    .font(.caption2).foregroundStyle(.subtle)
            }
        }
    }

    private func skillBar(_ icon: VEXIcon, _ label: String, _ score: Int, fraction: Double, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StrokeIcon(icon, size: 14, relativeTo: .footnote).foregroundStyle(.secondary)
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text(score > 0 ? "\(score)" : "\u{2014}")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            LevelBar(fraction: fraction, colour: theme.accent, height: 8, delay: delay)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    func competitionHistory(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let events = (profile.events ?? [])
            .filter { season == nil || $0.seasonId == season }
            .sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
        if !events.isEmpty {
            card {
                SectionHeader("Events", detail: "Results and qualification rank")
                // No gaps between entries, so the rail runs unbroken.
                VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        timelineRail(event: event, rank: standings(profile, eventID: event.id).first?.rank,
                                     isFirst: index == 0, isLast: index == events.count - 1)
                        // The whole entry is the link - name, place, result
                        // and rank - so a thumb landing on any line of it
                        // opens the event, not just one landing on the title.
                        NavigationLink(value: event.ref.focused(on: number)) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(event.name).font(.subheadline.weight(.medium))
                                    Spacer(minLength: 8)
                                    if let day = event.day {
                                        Text(day.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    StrokeIcon(.chevronRight, size: 11, relativeTo: .caption2)
                                        .foregroundStyle(.subtle)
                                }
                                if let place = event.location, !place.isEmpty {
                                    Text(place).font(.caption).foregroundStyle(.secondary)
                                }
                                if let result = event.eliminationResult {
                                    Label {
                                        Text(result).foregroundStyle(.primary)
                                    } icon: {
                                        StrokeIcon(.trophy, size: 13, relativeTo: .caption).foregroundStyle(theme.accent)
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                                ForEach(standings(profile, eventID: event.id), id: \.self) { standing in
                                    if !program.isIQ, standing.wins + standing.losses + standing.ties > 0 {
                                        RecordBar(wins: standing.wins, losses: standing.losses,
                                                  ties: standing.ties, height: 5)
                                            .frame(maxWidth: 180)
                                            .padding(.top, 2)
                                    }
                                    Text(program.isIQ
                                         ? "Qualification #\(standing.rank) · high \(standing.highScore.map(String.init) ?? "\u{2014}")"
                                         : "Qualification #\(standing.rank) · \(standing.record)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                }
            }
        }
    }

    /// The line down the left of the events, with each event's qualifying
    /// place set on it: medals for the top three, a trophy ring for an event
    /// they won outright.
    private func timelineRail(event: TeamEvent, rank: Int?, isFirst: Bool, isLast: Bool) -> some View {
        let won = event.eliminationResult.map {
            $0.localizedCaseInsensitiveContains("champion") || $0.localizedCaseInsensitiveContains("winner")
        } ?? false
        return VStack(spacing: 0) {
            Rectangle().fill(isFirst ? Color.clear : Color.hairline).frame(width: 2, height: 10)
            ZStack {
                if let rank {
                    PlaceBadge(rank, size: 34)
                } else {
                    Circle().fill(theme.surfaceRaised).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 2))
                        .frame(width: 34, height: 20)
                }
                if won {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.gold, lineWidth: 2)
                        .frame(width: 42, height: 42)
                }
            }
            Rectangle().fill(isLast ? Color.clear : Color.hairline).frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 44)
        .accessibilityHidden(true)
    }

    private func standings(_ profile: TeamProfileResponse, eventID: Int) -> [TeamEventStanding] {
        (profile.rankings ?? []).filter { $0.eventId == eventID }
    }

    @ViewBuilder
    func awards(_ profile: TeamProfileResponse, season: Int?) -> some View {
        let awards = (profile.awards ?? []).filter { season == nil || $0.seasonId == season }
        if !awards.isEmpty {
            card {
                SectionHeader("Trophy cabinet", detail: "\(awards.count) award\(awards.count == 1 ? "" : "s") this season")
                let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(awards.enumerated()), id: \.offset) { index, award in
                        awardTile(award).entrance(index, shown: awardsShown)
                    }
                }
                .onFirstVisible { awardsShown = true }
            }
        }
    }

    /// Gold for the awards that win a place at the next level, the accent
    /// for the rest.
    private func awardTile(_ award: Award) -> some View {
        let title = award.title ?? "Award"
        let top = ["Excellence", "Champion", "Tournament Finalist", "Design", "Skills Champion"]
            .contains { title.localizedCaseInsensitiveContains($0) }
        let colour: Color = top ? .gold : theme.accent
        // "Excellence Award (VRC/VEXU/VAIRC)" - the bracket is noise here.
        let short = title.components(separatedBy: " (").first ?? title
        return VStack(alignment: .leading, spacing: 8) {
            StrokeIcon(.trophy, size: 22)
                .foregroundStyle(colour)
                .frame(width: 40, height: 40)
                .background(colour.opacity(0.14), in: Circle())
            Text(short).font(.subheadline.weight(.semibold)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let event = award.event {
                Text(event).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            LinearGradient(colors: [colour.opacity(0.10), theme.surfaceRaised], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
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
    /// The same, for a VEX IQ event: teamwork matches still to play.
    private(set) var upcomingIQ: [TeamworkMatch] = []
    private(set) var hasOriginMatches = false
    /// Why a season could not be loaded, for the retry in its place.
    private(set) var seasonError: [Int: String] = [:]
    private var loadingSeasons: Set<Int> = []
    private let api = VEXRankAPI.shared

    /// Fetches `season`'s rows and folds them into the profile, unless they
    /// are already there. The first load covers one season; this covers the
    /// rest as the reader asks for them.
    @MainActor
    func ensure(season: Int, number: String) async {
        guard let current = profile, !current.hasLoaded(season: season),
              loadingSeasons.insert(season).inserted else { return }
        defer { loadingSeasons.remove(season) }
        seasonError[season] = nil
        do {
            let scoped = try await api.teamProfile(number: number, season: season)
            // Merged into whatever is there now, not the profile this began
            // with: another season may have landed while this one was loading.
            profile = profile?.merging(scoped) ?? scoped
        } catch {
            seasonError[season] = error.localizedDescription
        }
    }

    /// Fetched separately and allowed to fail quietly: the schedule is a bonus
    /// on top of the profile, and a profile that loaded should not report an
    /// error because an extra request did not.
    @MainActor
    private func loadUpcoming(number: String) async {
        guard let event = profile?.currentEvent() else { return }
        guard let detail = try? await api.eventDetail(id: String(event.id)) else { return }
        if detail.isIQ {
            let left = detail.iqMatches(for: number).filter { !$0.isPlayed }
            guard !left.isEmpty else { return }
            currentEvent = event
            upcomingIQ = left
            return
        }
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

    /// Clears the error first, so the spinner shows while it tries again.
    @MainActor
    func retry(ref: TeamRef, ranking: TeamRanking?, program: Program) async {
        error = nil
        await load(ref: ref, ranking: ranking, program: program)
    }

    @MainActor
    func load(ref: TeamRef, ranking: TeamRanking?, program: Program = .v5rc) async {
        guard profile == nil else { return }
        let number = ref.number

        // Only the schedule needs the profile first - it reads the team's
        // current event out of it. The event the reader arrived from and the
        // world ranking are answerable straight away, so they are started here
        // rather than queued behind two round trips they do not depend on.
        async let origin: Void = loadOrigin(ref)
        async let ranked: RankingsResponse? = ranking == nil ? try? await api.rankings() : nil

        // One season, not the whole career: uncached, the all-seasons profile
        // took 3 to 14 seconds against about half a second for this. Other
        // seasons are fetched when the reader picks them - see `ensure`.
        let season = await api.currentSeason()
        // A team opened before draws from its last copy while this one loads.
        if let known = await api.lastKnownTeamProfile(number: number, season: season) {
            profile = known
        }
        // A team opened for the first time: its official records straight from
        // events.vex, shown while the Worker works out the rating graph. Only
        // into an empty screen - the Worker's profile merges over it, and a
        // late direct answer never replaces what the Worker already sent.
        let direct = Task { @MainActor in
            guard let found = await DirectProfile.profile(number: number, season: season, program: program),
                  self.profile == nil else { return }
            self.profile = found
        }
        do {
            let fresh = try await api.teamProfile(number: number, season: season)
            // A server that predates VEX IQ ignores the program and answers
            // with the V5 team of that number. Shown as unavailable, never as
            // the wrong team.
            if program.isIQ && fresh.program != Program.viqrc.rawValue {
                profile = nil
                self.error = "This team's VEX IQ profile is not available yet."
                return
            }
            // Folded in rather than assigned: a season picked while this was
            // loading has already been merged into what is on screen.
            profile = profile?.merging(fresh) ?? fresh
        } catch {
            // Keep the saved copy if there is one; it is only a little old.
            // Nor is it an error while events.vex may still answer directly.
            if profile == nil { await direct.value }
            if profile == nil { self.error = error.localizedDescription }
        }

        await loadUpcoming(number: number)
        await origin

        // Best effort: a team outside the published ranking simply has none.
        // Only rows the server marked as this program's: an older server
        // answers an IQ request with V5 rows, and a V5 team of the same number
        // would otherwise lend its rating to an IQ profile.
        if let rankings = await ranked, !program.isIQ || rankings.program == Program.viqrc.rawValue {
            resolvedRanking = rankings.rankings.first {
                $0.number.caseInsensitiveCompare(number) == .orderedSame
            }
        }
    }
}

/// The profile's sections in outline while they load: the season card with
/// its ring and tiles, the rating chart, the first events - each where it
/// will land, so nothing below moves when the real ones arrive.
@available(iOS 17.0, *)
private struct ProfilePlaceholder: View {
    @Environment(\.vexTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                PlaceholderBlock(width: 170, height: 18)
                HStack(spacing: 18) {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 11)
                        .frame(width: 101, height: 101)
                        .padding(5.5)
                    VStack(alignment: .leading, spacing: 10) {
                        PlaceholderBlock(width: 150, height: 22)
                        PlaceholderBlock(height: 10, radius: 5)
                        PlaceholderBlock(width: 160, height: 10)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            PlaceholderBlock(width: 70, height: 10)
                            PlaceholderBlock(width: 44, height: 22)
                            PlaceholderBlock(width: 90, height: 8)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            card {
                PlaceholderBlock(width: 160, height: 18)
                // A flat wave where the rating line will run.
                ChartOutline()
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(height: 150)
            }
            card {
                PlaceholderBlock(width: 90, height: 18)
                ForEach(0..<3, id: \.self) { row in
                    PlaceholderRow(badge: true, lines: 3, trailing: false, seed: row)
                }
            }
        }
        .shimmering()
        .loadingPlaceholder()
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).vexCard()
    }
}

@available(iOS 17.0, *)
private struct ChartOutline: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let ys: [CGFloat] = [0.7, 0.55, 0.62, 0.4, 0.45, 0.25, 0.32]
            for (i, y) in ys.enumerated() {
                let point = CGPoint(x: rect.width * CGFloat(i) / CGFloat(ys.count - 1), y: rect.height * y)
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }
}
