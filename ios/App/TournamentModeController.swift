import ActivityKit
import BackgroundTasks
import SwiftUI
import VEXRankKit

/// Tournament mode: one team followed through an event's qualifiers on the
/// Lock Screen and in the Dynamic Island (Shared/TournamentActivity.swift,
/// Widget/TournamentWidget.swift).
///
/// The app is the only thing that can refresh the activity - there is no push
/// server behind it - so it refreshes every 30 seconds while open, and asks
/// for background refreshes while closed. iOS decides when those run; the
/// card marks itself stale when one has not come for a while, and its
/// countdown to the team's match keeps ticking either way.
@available(iOS 17.0, *)
@MainActor
@Observable
final class TournamentModeController {
    static let shared = TournamentModeController()
    static let refreshTaskID = "com.vexrank.app.tournament"

    /// The team and event being followed, when tournament mode is on.
    private(set) var team: String?
    private(set) var eventID: String?
    private(set) var status: TournamentStatus?
    private(set) var error: String?

    private var activity: Activity<TournamentActivityAttributes>?
    private var loop: Task<Void, Never>?
    private let api = VEXRankAPI.shared

    private init() {
        // Tournament mode outlives the app: pick up an activity left running
        // by the last launch rather than starting a second one beside it.
        if let running = Activity<TournamentActivityAttributes>.activities.first {
            activity = running
            team = running.attributes.team
            eventID = running.attributes.eventID
        }
    }

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isFollowing(team: String, event: String) -> Bool {
        self.team?.uppercased() == team.uppercased() && eventID == event
    }

    /// Starts following `team` at the event in `detail`, replacing whichever
    /// team was followed before.
    func start(team: String, event: EventRef, detail: EventDetailResponse) async {
        error = nil
        await stop()
        guard let status = detail.tournamentStatus(for: team, now: TournamentClock.replayNow) else {
            error = "\(team) has no qualification matches here."
            return
        }
        let attributes = TournamentActivityAttributes(team: team, eventName: detail.event.name, eventID: event.id)
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: content(status),
                                            pushType: nil)
            self.team = team
            self.eventID = event.id
            self.status = status
            resume()
        } catch {
            self.error = "Couldn't start the Live Activity: \(error.localizedDescription)"
        }
    }

    func stop() async {
        loop?.cancel()
        loop = nil
        for running in Activity<TournamentActivityAttributes>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        team = nil
        eventID = nil
        status = nil
    }

    /// Keeps the activity current while the app is open. Called on start and
    /// whenever the app comes to the foreground.
    func resume() {
        guard activity != nil, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        scheduleBackgroundRefresh()
    }

    /// The app is going to the background: stop the loop, and leave the
    /// refreshing to the background task.
    func pause() {
        loop?.cancel()
        loop = nil
        scheduleBackgroundRefresh()
    }

    /// One refresh: read the event fresh and update the card. Ends the
    /// activity once the team's qualifiers are over.
    func refresh() async {
        guard let activity, let eventID else { return }
        let team = activity.attributes.team
        do {
            let detail = try await api.eventDetail(id: eventID, fresh: true)
            guard let status = detail.tournamentStatus(for: team, now: TournamentClock.replayNow) else { return }
            self.status = status
            self.error = nil
            if status.phase == .done {
                // Left up a while, so the team sees it finished rather than
                // the card just vanishing.
                await activity.end(content(status), dismissalPolicy: .after(.now.addingTimeInterval(20 * 60)))
                loop?.cancel()
                loop = nil
                self.activity = nil
                self.team = nil
                self.eventID = nil
            } else {
                await activity.update(content(status))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scheduleBackgroundRefresh() {
        guard activity != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(2 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func content(_ status: TournamentStatus) -> ActivityContent<TournamentActivityAttributes.ContentState> {
        let state = TournamentActivityAttributes.ContentState(
            phase: status.phase.rawValue,
            currentLabel: status.current?.label,
            currentStarted: status.current?.started,
            currentScheduled: status.current?.scheduled,
            nextLabel: status.next?.label,
            nextAlliance: status.next?.alliance,
            nextPartners: status.next?.partners,
            nextField: status.next?.field,
            nextScheduled: status.next?.scheduled,
            nextEstimated: status.estimatedStart,
            matchesUntil: status.matchesUntil,
            updated: .now)
        // A qualifier takes a few minutes; a count older than ten is likely
        // wrong, and the card says when it was last right.
        return ActivityContent(state: state, staleDate: .now.addingTimeInterval(10 * 60))
    }
}
