import Foundation

/// An official ruling on one team in one qualification match: its result
/// changed from what the scores say. Mirrors website/lib/disqualifications.mjs.
public enum MatchRuling: String, Sendable, Hashable {
    /// VEX IQ: the team's station scored less than its partner's (they share
    /// one score, so they differ only when this team was disqualified or did
    /// not show). OpenScout's rule.
    case dq
    /// V5: the standings count a win on score as a loss.
    case ruledLoss
    /// V5: the standings count a loss or tie on score as a win.
    case ruledWin

    public var label: String {
        switch self {
        case .dq: return "DQ"
        case .ruledLoss: return "RULED LOSS"
        case .ruledWin: return "RULED WIN"
        }
    }

    public var explanation: String {
        switch self {
        case .dq: return "Disqualified or did not show: this station scored less than its partner's, though they share one score."
        case .ruledLoss: return "The official standings count this as a loss although the alliance won on score."
        case .ruledWin: return "The official standings count this as a win although the alliance did not win on score."
        }
    }
}

/// Rulings at an event, only where the data makes them certain.
///
/// V5 match records carry no DQ flag and the standings are not always
/// reproducible from the scores, so no cause is claimed: a team whose official
/// record has k fewer wins than its scores give, and that won exactly k matches
/// on score, had those counted as losses (and likewise for wins). A gap that
/// could sit in more than one match marks nothing; the team is `unresolved`.
public struct OfficialRulings: Sendable {
    public var byMatch: [Int: [String: MatchRuling]] = [:]
    public var unresolved: [String] = []

    public init() {}

    public func ruling(match: Int, team: String) -> MatchRuling? {
        byMatch[match]?[team.uppercased()]
    }

    mutating func add(_ match: Int, _ team: String, _ ruling: MatchRuling) {
        byMatch[match, default: [:]][team.uppercased()] = ruling
    }
}

extension Division {
    public func officialRulings(iq: Bool) -> OfficialRulings {
        var rulings = OfficialRulings()
        let played = (matches ?? []).filter { $0.isQualification && $0.isPlayed && ($0.alliances ?? []).count == 2 }
        if iq {
            for match in played {
                let alliances = match.alliances ?? []
                guard let first = alliances[0].score, let second = alliances[1].score, first != second else { continue }
                for team in alliances[first < second ? 0 : 1].numbers { rulings.add(match.id, team, .dq) }
            }
            return rulings
        }
        var results: [String: (name: String, won: [Int], lost: [Int], tied: [Int])] = [:]
        for match in played {
            let alliances = match.alliances ?? []
            for (own, other) in [(alliances[0], alliances[1]), (alliances[1], alliances[0])] {
                let mine = own.score ?? 0, theirs = other.score ?? 0
                for team in own.numbers {
                    var entry = results[team.uppercased()] ?? (team, [], [], [])
                    if mine > theirs { entry.won.append(match.id) } else if mine < theirs { entry.lost.append(match.id) } else { entry.tied.append(match.id) }
                    results[team.uppercased()] = entry
                }
            }
        }
        for row in rankings {
            guard let mine = results[row.team.name.uppercased()] else { continue }
            let fewer = mine.won.count - row.wins
            let more = row.wins - mine.won.count
            if fewer > 0 {
                if fewer == mine.won.count && row.ties == mine.tied.count {
                    for id in mine.won { rulings.add(id, mine.name, .ruledLoss) }
                } else { rulings.unresolved.append(mine.name) }
            } else if more > 0 {
                let notWon = mine.lost + mine.tied
                if more == notWon.count { for id in notWon { rulings.add(id, mine.name, .ruledWin) } } else { rulings.unresolved.append(mine.name) }
            } else if row.losses != mine.lost.count || row.ties != mine.tied.count {
                rulings.unresolved.append(mine.name)
            }
        }
        return rulings
    }
}

extension EventDetailResponse {
    /// Every division's rulings at this event.
    public var officialRulings: OfficialRulings {
        var all = OfficialRulings()
        for division in divisions {
            let rulings = division.officialRulings(iq: isIQ)
            all.byMatch.merge(rulings.byMatch) { first, _ in first }
            all.unresolved += rulings.unresolved
        }
        return all
    }
}
