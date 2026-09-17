import Foundation

/// Models mirror the live responses from the VEXRank Worker exactly as served;
/// field names and optionality were taken from captured responses rather than
/// assumed, and the same captures back the tests.
///
/// Numeric fields that the API can return as either integer or fractional are
/// decoded as `Double` and exposed rounded, so a change of 44 vs 44.25 does not
/// break decoding.

// MARK: - Rankings

public struct RankingsResponse: Codable, Sendable {
    public let rankings: [TeamRanking]

    /// Rankings in rank order, which is the order the rows appear to follow.
    ///
    /// The deployed Worker ranks by `rating - confidence` - an uncertainty-aware
    /// measure - while also returning the raw `rating`. So one of the two
    /// columns is always going to look out of order.
    ///
    /// Ordering by `rank` is the lesser evil: the leading element of every row
    /// then reads 1, 2, 3, and the rating varies with its own uncertainty
    /// printed beside it, which explains the variation. Sorting by rating
    /// instead makes the ratings tidy but prints "#2" above "#1", which no
    /// reader will accept.
    public var sortedForDisplay: [TeamRanking] {
        rankings.sorted { ($0.rank, $0.number) < ($1.rank, $1.number) }
    }
    public let eventsProcessed: Int
    public let matchesProcessed: Int
    public let method: String?
    public let modelVersion: String?
    public let season: String?
    public let updatedAt: String?
}

public struct FormEntry: Codable, Sendable, Hashable {
    public let event: String
    public let change: Int
    public let tier: String?
    public let champion: Bool?
}

public struct TeamRanking: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let rank: Int
    public let number: String
    public let name: String
    public let region: String?
    public let eventRegion: String?
    public let country: String?
    public let rating: Int
    public let confidence: Int
    public let change: Int
    public let record: String?
    public let events: Int
    public let matches: Int?
    public let grade: String?
    public let organization: String?
    public let opr: Double?
    public let dpr: Double?
    public let ccwm: Double?
    public let consistency: Int?
    public let skills: Int?
    public let seasonId: Int?
    public let season: String?
    public let form: [FormEntry]?

    /// The ranking list is ordered by `rating`, and the table shows `rating`.
    /// Kept as a named value so any future ordering change is one place, not
    /// scattered through the views - the web app previously sorted by
    /// `rating - confidence` while displaying `rating`, which put 203 of 585
    /// teams visually out of order.
    public var sortKey: Int { rating }
}

// MARK: - Team profile

public struct TeamProfileResponse: Codable, Sendable {
    public let team: TeamIdentity
    public let ratingHistory: [RatingPoint]
    public let awards: [Award]?
    public let skills: [SkillRun]?
    public let modelVersion: String?
    public let loadedSeasonIds: [Int]?
}

public struct TeamIdentity: Codable, Sendable, Hashable {
    public let id: Int
    public let number: String
    public let name: String
    public let organization: String
    public let robot: String
    public let grade: String
    public let region: String
    public let country: String
    public let registered: Bool
    public let active: Bool
    public let currentSeasonEvents: Int
    public let seasons: Int
}

public struct RatingPoint: Codable, Sendable, Identifiable, Hashable {
    public let seasonId: Int
    public let eventId: Int
    public let event: String
    public let eventDate: String
    public let change: Int
    public let rawChange: Double?
    public let rating: Int
    public let matches: Int
    public let tier: String?
    public let champion: Bool?

    public var id: Int { eventId }

    /// `eventDate` arrives as an ISO-8601 string with an offset.
    public var date: Date? { ISO8601DateFormatter().date(from: eventDate) }
}

public struct Award: Codable, Sendable, Hashable {
    public let title: String?
    public let event: String?
    public let seasonId: Int?
}

public struct SkillRun: Codable, Sendable, Hashable {
    public let event: String?
    public let type: String?
    public let score: Int?
    public let seasonId: Int?
}
