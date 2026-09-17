import SwiftUI
import Charts
import VEXRankKit

@available(iOS 17.0, *)
struct TeamProfileView: View {
    let number: String
    /// Present when arriving from the list; absent on a deep link, where the
    /// profile fetch supplies everything.
    var ranking: TeamRanking?

    /// From the list when present, otherwise resolved by the model.
    private var row: TeamRanking? { ranking ?? model.resolvedRanking }
    @Environment(\.vexTheme) private var theme
    @State private var model = TeamProfileModel()

    var body: some View {
        // The viewport height is published to the reveal modifier, which needs
        // to know what "scrolled into view" means.
        GeometryReader { viewport in
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
                            seasonBand(profile).reveal()
                            if profile.ratingHistory.count > 1 { chart(profile).reveal() }
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
            .environment(\.revealViewportHeight, viewport.size.height)
        }
        .background(theme.page)
        .navigationTitle(number)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(number: number, ranking: ranking) }
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
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LIVE VCR").font(.caption2.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(row.map { "\($0.rating)" } ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }

    private func seasonBand(_ profile: TeamProfileResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SEASON SUMMARY").font(.caption2.weight(.semibold)).tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Text("ON\nRECORD").font(.system(size: 34, weight: .semibold)).lineSpacing(-4)

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                metric("Status", profile.team.active ? "Active" : "Inactive",
                       "\(profile.team.currentSeasonEvents) current-season events")
                metric("Season events", "\(row?.events ?? profile.team.currentSeasonEvents)", "Official competitions")
                metric("Record", row?.record ?? "—", "\(row?.matches ?? 0) matches")
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

    private func chart(_ profile: TeamProfileResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tournament rating movement").font(.title3.weight(.semibold))
            GrowingRatingChart(history: profile.ratingHistory, accent: theme.accent)
                .frame(height: 220)
            Text("The published ranking uses a rolling sample of the season's most recent events, so this line can run ahead of the rating in the table.")
                .font(.caption2).foregroundStyle(.secondary)
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
    private let api = VEXRankAPI()

    @MainActor
    func load(number: String, ranking: TeamRanking?) async {
        guard profile == nil else { return }
        do { profile = try await api.teamProfile(number: number) }
        catch { self.error = error.localizedDescription }

        guard ranking == nil else { return }
        // Best effort: a team outside the published ranking simply has none.
        if let rankings = try? await api.rankings() {
            resolvedRanking = rankings.rankings.first {
                $0.number.caseInsensitiveCompare(number) == .orderedSame
            }
        }
    }
}
