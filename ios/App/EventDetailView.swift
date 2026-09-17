import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
struct EventDetailView: View {
    let event: VEXEvent
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
                                HStack {
                                    Text("#\(row.rank)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 44, alignment: .leading)
                                        .monospacedDigit()
                                    // The API carries the team number in `name`.
                                    Text(row.team.name).font(.subheadline)
                                    Spacer()
                                    Text(row.record).font(.caption).foregroundStyle(.secondary)
                                        .monospacedDigit()
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

                if detail.divisions.allSatisfy({ $0.rankings.isEmpty }) && detail.awards.isEmpty && skills.isEmpty {
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
