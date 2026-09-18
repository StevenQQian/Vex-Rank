import Foundation

/// A team's contribution ratings at one event.
public struct TeamEventStats: Sendable, Hashable {
    /// Offensive Power Rating: the points this team is estimated to add to
    /// whichever alliance it is on.
    public let opr: Double
    /// Defensive Power Rating: the points its opponents are estimated to score
    /// against it. Lower is better.
    public let dpr: Double
    /// Calculated Contribution to Winning Margin.
    public var ccwm: Double { opr - dpr }
}

extension Division {
    /// OPR, DPR and CCWM solved from this division's own qualification matches.
    ///
    /// The API publishes WP, AP and SP per event but not these, because they
    /// are not counted - they are fitted. Each played qualification match says
    /// "these two teams together scored this much", and the ratings are the
    /// per-team values that best explain every such statement at once, in the
    /// least-squares sense.
    ///
    /// Solved through the normal equations: `A` holds, at (i, j), how many
    /// matches i and j played together, and on its diagonal how many i played
    /// at all; `b` holds each team's total alliance score. Elimination matches
    /// are excluded, as they are everywhere else - alliances there are chosen
    /// rather than drawn, so they say nothing about a team on its own.
    public func powerRatings() -> [String: TeamEventStats] {
        let played = qualification.filter(\.isPlayed)
        guard !played.isEmpty else { return [:] }

        // Each match contributes twice: once per alliance.
        var sides: [(teams: [String], scored: Double, conceded: Double)] = []
        for match in played {
            guard let red = match.red, let blue = match.blue,
                  let redScore = red.score, let blueScore = blue.score else { continue }
            let redTeams = red.numbers.map { $0.uppercased() }
            let blueTeams = blue.numbers.map { $0.uppercased() }
            guard !redTeams.isEmpty, !blueTeams.isEmpty else { continue }
            sides.append((redTeams, Double(redScore), Double(blueScore)))
            sides.append((blueTeams, Double(blueScore), Double(redScore)))
        }
        guard !sides.isEmpty else { return [:] }

        let teams = Array(Set(sides.flatMap(\.teams))).sorted { TeamNumber.precedes($0, $1) }

        // Not enough play to fit anything meaningful.
        //
        // Each match gives two equations and involves four teams, so the fit
        // needs roughly as many played matches as there are teams for each to
        // be seen about four times. Below that the system is underdetermined
        // and the solver answers with numbers that look like ratings and are
        // not: an event 39 matches into a 219-match schedule produced an OPR of
        // -70 and a CCWM of -222. Publishing those is worse than publishing
        // nothing, so nothing is what it returns.
        guard played.count >= teams.count else { return [:] }
        let index = Dictionary(uniqueKeysWithValues: teams.enumerated().map { ($1, $0) })
        let n = teams.count


        var a = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var offence = [Double](repeating: 0, count: n)
        var defence = [Double](repeating: 0, count: n)

        for side in sides {
            let rows = side.teams.compactMap { index[$0] }
            for i in rows {
                offence[i] += side.scored
                defence[i] += side.conceded
                for j in rows { a[i][j] += 1 }
            }
        }

        // A team that played few matches, or always with the same partner,
        // leaves the system underdetermined. A small ridge keeps it solvable
        // and pulls those teams gently toward zero rather than to infinity.
        for i in 0..<n { a[i][i] += 1e-6 }

        guard let opr = Self.solve(a, offence), let dpr = Self.solve(a, defence) else { return [:] }
        return Dictionary(uniqueKeysWithValues: teams.enumerated().map { i, team in
            (team, TeamEventStats(opr: opr[i], dpr: dpr[i]))
        })
    }

    /// Gaussian elimination with partial pivoting. Returns nil if the system
    /// turns out to be singular anyway, which is better than returning numbers
    /// that mean nothing.
    static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        let n = vector.count
        guard n > 0, matrix.count == n else { return nil }
        var a = matrix
        var b = vector

        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(a[row][column]) > abs(a[pivot][column]) {
                pivot = row
            }
            guard abs(a[pivot][column]) > 1e-9 else { return nil }
            if pivot != column {
                a.swapAt(pivot, column)
                b.swapAt(pivot, column)
            }
            let head = a[column][column]
            for row in (column + 1)..<n {
                let factor = a[row][column] / head
                guard factor != 0 else { continue }
                for col in column..<n { a[row][col] -= factor * a[column][col] }
                b[row] -= factor * b[column]
            }
        }

        var solution = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var total = b[row]
            for col in (row + 1)..<n { total -= a[row][col] * solution[col] }
            solution[row] = total / a[row][row]
        }
        return solution
    }
}
