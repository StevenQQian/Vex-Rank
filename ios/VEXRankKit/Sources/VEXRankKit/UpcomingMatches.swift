import Foundation

/// A match a team is scheduled to play but has not played yet.
public struct UpcomingMatch: Identifiable, Sendable, Hashable {
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
    /// The matches `number` has still to play, in the order they will be
    /// played. Empty once the team's schedule is done, which is what the
    /// profile checks before showing anything.
    public func upcomingMatches(for number: String) -> [UpcomingMatch] {
        let wanted = number.uppercased()
        var found: [UpcomingMatch] = []

        for division in divisions {
            for match in division.matches ?? [] where !match.isPlayed {
                let red = match.red?.numbers ?? []
                let blue = match.blue?.numbers ?? []
                let onRed = red.contains { $0.uppercased() == wanted }
                let onBlue = blue.contains { $0.uppercased() == wanted }
                guard onRed || onBlue else { continue }

                let mine = onRed ? red : blue
                found.append(UpcomingMatch(
                    id: match.id,
                    name: match.name ?? "Match",
                    field: match.field,
                    scheduled: match.scheduled.flatMap { ISO8601DateFormatter().date(from: $0) },
                    division: division.name,
                    colour: onRed ? "red" : "blue",
                    partners: mine.filter { $0.uppercased() != wanted },
                    opponents: onRed ? blue : red
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
}
