import Foundation

public struct EventDetailResponse: Codable, Sendable {
    public let event: EventDetail
    public let teams: [EventTeam]
    public let divisions: [Division]
    public let awards: [EventAward]
    public let skills: [EventSkill]
}

public struct EventDetail: Codable, Sendable {
    public let id: Int
    public let sku: String?
    public let name: String
    public let start: String?
    public let end: String?
    public let location: EventLocation?

    public var venueLine: String {
        guard let location else { return "" }
        return [location.venue, location.city, location.region, location.country]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }
}

public struct EventLocation: Codable, Sendable {
    public let venue: String?
    public let city: String?
    public let region: String?
    public let country: String?
}

public struct EventTeam: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let number: String
    public let name: String?
    public let organization: String?
    public let grade: String?
}

public struct Division: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let rankings: [DivisionRanking]
    public let matches: [DivisionMatch]?
}

public struct DivisionRanking: Codable, Sendable, Identifiable, Hashable {
    public let rank: Int
    public let team: DivisionTeam
    public let wins: Int
    public let losses: Int
    public let ties: Int
    public let wp: Int?
    public let ap: Int?
    public let sp: Int?
    public let highScore: Int?

    public var id: Int { team.id }
    public var record: String { "\(wins)–\(losses)–\(ties)" }
}

public struct DivisionTeam: Codable, Sendable, Hashable {
    public let id: Int
    /// The API puts the team *number* in `name` here, and `code` is usually null
    /// - named as served rather than renamed, so the mapping stays obvious.
    public let name: String
    public let code: String?
}

public struct DivisionMatch: Codable, Sendable, Hashable {
    public let id: Int?
    public let name: String?
    public let round: Int?
}

public struct EventAward: Codable, Sendable, Hashable {
    public let title: String?
    public let teamWinners: [AwardWinner]?

    enum CodingKeys: String, CodingKey {
        case title
        case teamWinners = "teamWinners"
    }
}

public struct AwardWinner: Codable, Sendable, Hashable {
    public let team: EventTeamRef?
}

public struct EventTeamRef: Codable, Sendable, Hashable {
    public let id: Int?
    public let name: String?
}

public struct EventSkill: Codable, Sendable, Hashable {
    public let rank: Int?
    public let score: Int?
    public let type: String?
    public let team: EventTeamRef?
}

/// One team's combined skills result at an event.
public struct EventSkillLeader: Identifiable, Sendable, Hashable {
    public var id: String { number }
    public let number: String
    public let driver: Int
    public let programming: Int
    public var total: Int { driver + programming }
}

extension EventDetailResponse {
    /// The API serves one row per team *per skills type* ("driver",
    /// "programming"), but the standing people read is the combined total, so
    /// the rows are folded per team and ranked on the sum.
    public var skillsLeaderboard: [EventSkillLeader] {
        var driver: [String: Int] = [:]
        var programming: [String: Int] = [:]
        for entry in skills {
            guard let number = entry.team?.name, !number.isEmpty, let score = entry.score else { continue }
            switch entry.type {
            case "driver": driver[number] = max(driver[number] ?? 0, score)
            case "programming": programming[number] = max(programming[number] ?? 0, score)
            default: continue
            }
        }
        return Set(driver.keys).union(programming.keys)
            .map { EventSkillLeader(number: $0, driver: driver[$0] ?? 0, programming: programming[$0] ?? 0) }
            .sorted { $0.total == $1.total ? $0.number < $1.number : $0.total > $1.total }
    }
}
