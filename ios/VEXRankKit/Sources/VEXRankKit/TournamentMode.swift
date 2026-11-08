import Foundation

/// Where an event's qualification schedule stands, read for one team: the
/// match on the field right now, and how far off the team's own next one is.
///
/// "Right now" comes from each match's `started` time - the moment the field
/// was started in Tournament Manager - not from which matches have scores.
/// Scores are posted a minute or two after a match ends, so the last scored
/// match is always behind the field; and the schedule is no better, because
/// events run late. The latest-started match is the one being played, until
/// its score lands, at which point the field is waiting on the one after it.
public struct TournamentStatus: Sendable, Hashable {
    public enum Phase: String, Sendable, Codable {
        /// No qualifier has been started yet.
        case waiting
        /// Qualifiers are under way and the team still has one to play.
        case running
        /// The team has played every qualifier it was given.
        case done
    }

    /// One qualification match, as tournament mode shows it.
    public struct Slot: Sendable, Hashable {
        public let id: Int
        /// "Q14".
        public let label: String
        public let field: String?
        public let scheduled: Date?
        /// When the field was started; nil until it is.
        public let started: Date?
        /// "red" or "blue" for the team's side; nil for a match it is not in,
        /// and for VEX IQ, where both teams share one alliance.
        public let alliance: String?
        /// Who the team plays it with: alliance partners in V5, the teamwork
        /// partner in VEX IQ - what an IQ team checks instead of a colour.
        public let partners: [String]
    }

    public let phase: Phase
    public let division: String
    /// The match being played, or the one the field is waiting to start.
    public let current: Slot?
    /// The team's next qualifier. The same match as `current` when it is
    /// the team's turn.
    public let next: Slot?
    /// Matches between the one on the field and the team's next: 0 when the
    /// team is the one on the field (or about to be).
    public let matchesUntil: Int?
    /// When the team's next match should start, moved by however late the
    /// event is running - the current match's start against its schedule.
    public let estimatedStart: Date?

    /// Whether the team is the one on the field now, or the next one on.
    public var isTeamUp: Bool { matchesUntil == 0 }
}

extension EventDetailResponse {
    /// Tournament mode's reading of the schedule for `number`, or nil when the
    /// team has no qualification matches here.
    ///
    /// `now` exists for replaying a finished event: a match started after it
    /// counts as not started, and one started before it as unscored only
    /// while it is the latest - the payload does not say when a score landed.
    public func tournamentStatus(for number: String, now: Date? = nil) -> TournamentStatus? {
        let wanted = number.uppercased()
        func isTeams(_ match: DivisionMatch) -> Bool {
            (match.red?.numbers ?? []).contains { $0.uppercased() == wanted }
                || (match.blue?.numbers ?? []).contains { $0.uppercased() == wanted }
        }
        guard let division = divisions.first(where: { $0.qualification.contains(where: isTeams) })
        else { return nil }

        let quals = division.qualification
        let parser = ISO8601DateFormatter()
        func started(_ match: DivisionMatch) -> Date? {
            guard let date = match.started.flatMap(parser.date(from:)) else { return nil }
            if let now, date > now { return nil }
            return date
        }
        func scheduled(_ match: DivisionMatch) -> Date? { match.scheduled.flatMap(parser.date(from:)) }
        func slot(_ match: DivisionMatch) -> TournamentStatus.Slot {
            let onRed = (match.red?.numbers ?? []).contains { $0.uppercased() == wanted }
            let onBlue = (match.blue?.numbers ?? []).contains { $0.uppercased() == wanted }
            // V5 partners share the team's side; an IQ pair is split across
            // both "alliances", so its partner is everyone else in the match.
            let side = isIQ ? match.teamwork.teams : onRed ? (match.red?.numbers ?? []) : onBlue ? (match.blue?.numbers ?? []) : []
            return .init(id: match.id,
                         label: "Q\(match.matchnum ?? 0)",
                         field: match.field,
                         scheduled: scheduled(match),
                         started: started(match),
                         // VEX IQ puts both teams on one side; there is no
                         // plate to pick.
                         alliance: isIQ ? nil : (onRed ? "red" : onBlue ? "blue" : nil),
                         partners: (onRed || onBlue) ? side.filter { $0.uppercased() != wanted } : [])
        }

        // The latest-started match, by time rather than by number: a replayed
        // match is started again after the ones that followed it.
        let latest = quals.indices
            .compactMap { i in started(quals[i]).map { (i, $0) } }
            .max { $0.1 < $1.1 }?.0

        let nowIndex: Int
        if let latest {
            // Scored means it is over and the field waits on the next one.
            let scored = now == nil && quals[latest].isPlayed
            nowIndex = scored ? latest + 1 : latest
        } else {
            nowIndex = 0
        }

        let current = quals.indices.contains(nowIndex) ? slot(quals[nowIndex]) : nil
        guard let nextIndex = quals.indices.first(where: { $0 >= nowIndex && isTeams(quals[$0]) }) else {
            return TournamentStatus(phase: .done, division: division.name, current: current,
                                    next: nil, matchesUntil: nil, estimatedStart: nil)
        }
        let next = slot(quals[nextIndex])

        // How late the event is running, from the latest match that has both
        // times. Never early: a field does not start ahead of the schedule
        // often enough to promise a team that it will.
        var delay: TimeInterval = 0
        if let latest, let start = started(quals[latest]), let plan = scheduled(quals[latest]) {
            delay = max(0, start.timeIntervalSince(plan))
        }
        let estimate = next.started ?? next.scheduled.map { $0.addingTimeInterval(delay) }

        return TournamentStatus(phase: latest == nil ? .waiting : .running,
                                division: division.name,
                                current: current,
                                next: next,
                                matchesUntil: nextIndex - nowIndex,
                                estimatedStart: estimate)
    }

    /// Whether `date` falls inside the event's run, compared by calendar day
    /// for the same reason `TeamEvent.runs(on:)` is.
    public func isRunning(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let start = EventDay.parse(event.start) else { return false }
        let last = EventDay.parse(event.end) ?? start
        let today = calendar.startOfDay(for: date)
        return calendar.startOfDay(for: start) <= today && today <= calendar.startOfDay(for: last)
    }
}

/// The clock tournament mode reads. Normally the real one; `-tournament-clock
/// 2026-10-25T10:40:00-04:00` on launch starts it at that moment instead and
/// lets it run on from there, which replays a finished event as if it were
/// live - the only way to see the feature on a day nothing is being played.
public enum TournamentClock {
    private static let launched = Date()
    private static let replayStart: Date? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-tournament-clock"), args.indices.contains(i + 1) else { return nil }
        return ISO8601DateFormatter().date(from: args[i + 1])
    }()

    public static var isReplaying: Bool { replayStart != nil }

    /// The replay time, or nil when the clock is the real one.
    public static var replayNow: Date? {
        replayStart.map { $0.addingTimeInterval(Date().timeIntervalSince(launched)) }
    }

    public static var now: Date { replayNow ?? Date() }
}
