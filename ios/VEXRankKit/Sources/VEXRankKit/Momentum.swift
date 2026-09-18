import Foundation

/// One step of a team's run through a tournament.
public struct MomentumPoint: Identifiable, Sendable, Hashable {
    public let id: Int
    /// Position in the team's own match order, from 1.
    public let match: Int
    public let name: String
    /// This match's scoring margin from the team's side.
    public let margin: Int
    /// Running total of those margins - the momentum itself.
    public let cumulative: Int
    public let outcome: TeamMatch.Outcome
}

public enum TeamMomentum {
    /// A team's tournament momentum: the running sum of its scoring margins,
    /// match by match, in the order they were played.
    ///
    /// The same shape of reading as the season rating curve, over a single
    /// event. A cumulative margin rather than a win count because it says how
    /// much, not just whether: two narrow wins and one heavy loss is a
    /// different tournament from three narrow wins, and a win-loss line cannot
    /// tell them apart.
    ///
    /// Only played matches count. An unplayed one has no score, and carrying
    /// the last value forward would draw a flat line into the future as though
    /// it were a result.
    public static func points(from matches: [TeamMatch]) -> [MomentumPoint] {
        var running = 0
        var points: [MomentumPoint] = []
        for match in matches where match.isPlayed {
            guard let mine = match.scoreFor, let theirs = match.scoreAgainst else { continue }
            let margin = mine - theirs
            running += margin
            points.append(MomentumPoint(
                id: match.id,
                match: points.count + 1,
                name: match.name,
                margin: margin,
                cumulative: running,
                outcome: match.outcome
            ))
        }
        return points
    }

    /// The y range to draw, padded, and always including zero so that being
    /// level is visibly the middle rather than the floor.
    public static func range(_ points: [MomentumPoint]) -> ClosedRange<Double> {
        let values = points.map { Double($0.cumulative) } + [0]
        guard let low = values.min(), let high = values.max() else { return -1...1 }
        let padding = max(10, (high - low) * 0.15)
        return (low - padding)...(high + padding)
    }
}
