import Foundation

/// One match at an event, read from a particular team's point of view: their
/// side, their partners, who they faced, and how it went for them.
public struct TeamMatch: Identifiable, Sendable, Hashable {
    public enum Outcome: String, Sendable {
        case won, lost, tied, scheduled
    }

    public let id: Int
    public let name: String
    public let field: String?
    public let scheduled: Date?
    public let division: String
    /// "red" or "blue" - which side the team is on.
    public let colour: String
    /// The team's alliance partners, the team itself excluded.
    public let partners: [String]
    public let opponents: [String]
    /// Scores from this team's side, so "for" is always theirs.
    public let scoreFor: Int?
    public let scoreAgainst: Int?
    public let isPlayed: Bool

    public var outcome: Outcome {
        guard isPlayed, let scoreFor, let scoreAgainst else { return .scheduled }
        if scoreFor > scoreAgainst { return .won }
        if scoreFor < scoreAgainst { return .lost }
        return .tied
    }
}

/// A team's wins, losses and ties at one event.
public struct TeamEventRecord: Sendable, Hashable {
    public let wins: Int
    public let losses: Int
    public let ties: Int
    public let remaining: Int

    public var played: Int { wins + losses + ties }
    public var summary: String { "\(wins)\u{2013}\(losses)\u{2013}\(ties)" }

    public init(matches: [TeamMatch]) {
        wins = matches.filter { $0.outcome == .won }.count
        losses = matches.filter { $0.outcome == .lost }.count
        ties = matches.filter { $0.outcome == .tied }.count
        remaining = matches.filter { !$0.isPlayed }.count
    }
}

extension TeamEvent {
    public var endDay: Date? { (end ?? start).flatMap { ISO8601DateFormatter().date(from: $0) } }

    /// Whether `date` falls inside this event's run, compared by calendar day.
    ///
    /// The API timestamps events at midnight in the venue's own offset, so
    /// comparing instants would end an event several hours early or late for a
    /// reader in another time zone. A competition is a set of days.
    public func runs(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let start = day else { return false }
        let last = endDay ?? start
        let today = calendar.startOfDay(for: date)
        return calendar.startOfDay(for: start) <= today && today <= calendar.startOfDay(for: last)
    }
}

extension TeamProfileResponse {
    /// The competition this team is at right now, if any. The earliest one when
    /// two overlap, which happens where a league runs across a tournament.
    public func currentEvent(on date: Date = Date()) -> TeamEvent? {
        (events ?? [])
            .filter { $0.runs(on: date) }
            .sorted { ($0.day ?? .distantPast) < ($1.day ?? .distantPast) }
            .first
    }
}

extension EventDetailResponse {
    /// Every match `number` is in at this event, played and scheduled, in the
    /// order they are played.
    public func matches(for number: String) -> [TeamMatch] {
        let wanted = number.uppercased()
        var found: [TeamMatch] = []

        for division in divisions {
            for match in division.matches ?? [] {
                let red = match.red?.numbers ?? []
                let blue = match.blue?.numbers ?? []
                let onRed = red.contains { $0.uppercased() == wanted }
                let onBlue = blue.contains { $0.uppercased() == wanted }
                guard onRed || onBlue else { continue }

                let mine = onRed ? red : blue
                let played = match.isPlayed
                found.append(TeamMatch(
                    id: match.id,
                    name: match.name ?? "Match",
                    field: match.field,
                    scheduled: match.scheduled.flatMap { ISO8601DateFormatter().date(from: $0) },
                    division: division.name,
                    colour: onRed ? "red" : "blue",
                    partners: mine.filter { $0.uppercased() != wanted },
                    opponents: onRed ? blue : red,
                    // Only a played match has scores worth reading; an unplayed
                    // one carries 0 against 0, which would read as a nil-all
                    // draw rather than as a fixture.
                    scoreFor: played ? (onRed ? match.red?.score : match.blue?.score) : nil,
                    scoreAgainst: played ? (onRed ? match.blue?.score : match.red?.score) : nil,
                    isPlayed: played
                ))
            }
        }

        return found.sorted { a, b in
            // Scheduled time first where it exists, since that is what a team
            // in the pits is actually reading off the board.
            if let x = a.scheduled, let y = b.scheduled, x != y { return x < y }
            if (a.scheduled == nil) != (b.scheduled == nil) { return a.scheduled != nil }
            return a.id < b.id
        }
    }

    /// The matches `number` has still to play. Empty once their schedule is
    /// done, which is what the profile checks before showing anything.
    public func upcomingMatches(for number: String) -> [TeamMatch] {
        matches(for: number).filter { !$0.isPlayed }
    }
}
