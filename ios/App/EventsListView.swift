import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
struct EventsListView: View {
    @Environment(\.vexTheme) private var theme
    @State private var model = EventsModel()
    @State private var upcomingOnly = true
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            // Above the list rather than in the navigation bar, where a
            // segmented control gets squeezed down to "U A".
            Picker("Window", selection: $upcomingOnly) {
                Text("Upcoming").tag(true)
                Text("All").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            content
        }
        .background(theme.page)
        .searchable(text: $query, prompt: "Search events by name or place")
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading events…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load events", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
            }
        case .loaded(let events):
            let shown = filter(events)
            if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                list(shown)
            }
        }
    }

    private func filter(_ events: [VEXEvent]) -> [VEXEvent] {
        var shown = upcomingOnly ? events.filter(\.isUpcoming) : events
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            shown = shown.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.place.localizedCaseInsensitiveContains(trimmed)
            }
        }
        // Upcoming reads best soonest-first; history reads best newest-first.
        return shown.sorted { upcomingOnly ? $0.date < $1.date : $0.date > $1.date }
    }

    private func list(_ events: [VEXEvent]) -> some View {
        List(events) { event in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(event.day.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? event.date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    if let tier = event.tier, tier != "Official" {
                        Text(tier.uppercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    if let status = event.status {
                        Text(status).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(event.name).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 6) {
                    if !event.place.isEmpty {
                        Label(event.place, systemImage: "mappin.and.ellipse")
                    }
                    if let teams = event.teams, teams > 0 {
                        Text("· \(teams) teams")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .listRowBackground(theme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
    }
}

@available(iOS 17.0, *)
@Observable
final class EventsModel {
    enum State { case loading, loaded([VEXEvent]), failed(String) }
    private(set) var state: State = .loading
    private let api = VEXRankAPI()

    @MainActor
    func load() async {
        state = .loading
        do { state = .loaded(try await api.events().events) }
        catch { state = .failed(error.localizedDescription) }
    }
}
