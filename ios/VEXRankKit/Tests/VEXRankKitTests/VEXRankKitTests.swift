import XCTest
@testable import VEXRankKit

/// Decoding is tested against responses captured from the live Worker, not
/// hand-written samples: the point is to catch the API drifting away from the
/// models, which a sample I authored myself could never do.
final class DecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    func testDecodesLiveRankingsResponse() throws {
        let response = try JSONDecoder().decode(RankingsResponse.self, from: fixture("rankings"))
        XCTAssertGreaterThan(response.rankings.count, 100)
        XCTAssertGreaterThan(response.eventsProcessed, 0)

        let leader = try XCTUnwrap(response.rankings.first)
        XCTAssertEqual(leader.rank, 1)
        XCTAssertFalse(leader.number.isEmpty)
        XCTAssertGreaterThan(leader.rating, 0)
    }

    func testSortedForDisplayIsMonotonicInRank() throws {
        let response = try JSONDecoder().decode(RankingsResponse.self, from: fixture("rankings"))
        let ranks = response.sortedForDisplay.map(\.rank)
        // The rank badge leads every row, so it is the column that must be
        // ordered. Sorting by rating instead prints "#2" above "#1".
        XCTAssertEqual(ranks, ranks.sorted(), "rank must increase down the table")
        XCTAssertEqual(ranks.first, 1)
    }

    func testServerOrderIsNotYetMonotonic() throws {
        // Documents a live cross-system discrepancy rather than asserting the
        // app's behaviour: the deployed Worker sorts by rating - confidence but
        // returns rating, so its payload is not ordered by the number a table
        // shows. The web fix is merged but the API has not been redeployed.
        // When it is, this test should start failing - and that is the signal
        // to delete it and let the client trust the server order.
        let response = try JSONDecoder().decode(RankingsResponse.self, from: fixture("rankings"))
        let asServed = response.rankings.map(\.sortKey)
        let outOfOrder = zip(asServed, asServed.dropFirst()).filter { $1 > $0 }.count
        XCTAssertGreaterThan(outOfOrder, 0, "server order looks fixed now - rating and rank agree, so this note can go")
    }

    func testDecodesLiveTeamProfile() throws {
        let profile = try JSONDecoder().decode(TeamProfileResponse.self, from: fixture("team"))
        XCTAssertEqual(profile.team.number, "31260X")
        XCTAssertFalse(profile.team.region.isEmpty)
        XCTAssertFalse(profile.ratingHistory.isEmpty)
    }

    func testRatingHistoryDatesParse() throws {
        let profile = try JSONDecoder().decode(TeamProfileResponse.self, from: fixture("team"))
        for point in profile.ratingHistory {
            XCTAssertNotNil(point.date, "could not parse eventDate \(point.eventDate)")
        }
    }

    func testFractionalRawChangeDoesNotBreakDecoding() throws {
        let profile = try JSONDecoder().decode(TeamProfileResponse.self, from: fixture("team"))
        // change is an Int, rawChange is fractional; decoding both is the point.
        XCTAssertTrue(profile.ratingHistory.contains { ($0.rawChange ?? 0) != Double($0.change) })
    }
}

final class StrokeGlyphTests: XCTestCase {
    func testCoversDigitsAndLetters() {
        XCTAssertTrue(StrokeGlyphs.canDraw("0123456789"))
        XCTAssertTrue(StrokeGlyphs.canDraw("ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        XCTAssertEqual(StrokeGlyphs.glyphs.count, 36)
    }

    func testRealTeamNumbersAreDrawable() {
        for number in ["31260X", "2775V", "9123Y", "1940H", "16610A"] {
            XCTAssertTrue(StrokeGlyphs.canDraw(number), "\(number) should be drawable")
        }
    }

    func testLowercaseIsAccepted() {
        XCTAssertTrue(StrokeGlyphs.canDraw("31260x"))
        XCTAssertEqual(StrokeGlyphs.strokes(for: "x"), StrokeGlyphs.strokes(for: "X"))
    }

    func testUnsupportedCharactersAreRejectedRatherThanDropped() {
        XCTAssertFalse(StrokeGlyphs.canDraw("31260-X"))
        XCTAssertFalse(StrokeGlyphs.canDraw(""))
        XCTAssertNil(StrokeGlyphs.strokes(for: "-"))
    }

    func testStrokeOrderMatchesTheWebSource() {
        // H is left stem, crossbar, right stem - the order corrected on the web.
        XCTAssertEqual(StrokeGlyphs.strokes(for: "H"), ["M10,6 L10,95", "M10,50 L50,50", "M50,6 L50,95"])
        // Multi-stroke glyphs keep their stroke counts.
        XCTAssertEqual(StrokeGlyphs.strokes(for: "X")?.count, 2)
        XCTAssertEqual(StrokeGlyphs.strokes(for: "E")?.count, 4)
        XCTAssertEqual(StrokeGlyphs.strokes(for: "8")?.count, 1)
    }

    func testEveryStrokeStartsWithAMoveCommand() {
        for (character, strokes) in StrokeGlyphs.glyphs {
            for stroke in strokes {
                XCTAssertTrue(stroke.hasPrefix("M"), "\(character) has a stroke not starting with M: \(stroke)")
            }
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The parser feeds both the drawing and the timing, so a wrong length would
/// silently make strokes take the wrong time rather than look wrong.
final class StrokePathTests: XCTestCase {
    func testStraightLineLengthIsExact() {
        // The H crossbar runs x 10 -> 50 at constant y.
        let parsed = StrokePathParser.parse("M10,50 L50,50")
        XCTAssertEqual(parsed.approximateLength, 40, accuracy: 0.001)
    }

    func testPolylineSumsItsSegments() {
        // V: down 89 then back up 89, across 23 each way.
        let parsed = StrokePathParser.parse("M7,6 L30,95 L53,6")
        let leg = (89.0 * 89.0 + 23.0 * 23.0).squareRoot()
        XCTAssertEqual(parsed.approximateLength, leg * 2, accuracy: 0.01)
    }

    func testCurveLengthExceedsItsChord() {
        let parsed = StrokePathParser.parse("M30,6 C12,6 4,28 4,50")
        let chord = hypot(30.0 - 4.0, 6.0 - 50.0)
        XCTAssertGreaterThan(parsed.approximateLength, chord)
        XCTAssertLessThan(parsed.approximateLength, chord * 2, "flattening should not wildly overshoot")
    }

    func testEveryGlyphStrokeParsesToNonZeroLength() {
        for (character, strokes) in StrokeGlyphs.glyphs {
            for stroke in strokes {
                let parsed = StrokePathParser.parse(stroke)
                XCTAssertGreaterThan(parsed.approximateLength, 1,
                                     "\(character) stroke measured near zero: \(stroke)")
                XCTAssertFalse(parsed.path.isEmpty, "\(character) produced an empty path")
            }
        }
    }

    func testZeroIsAClosedLoopLongerThanItsBoundingBox() {
        let zero = try! XCTUnwrap(StrokeGlyphs.strokes(for: "0")).first!
        XCTAssertGreaterThan(StrokePathParser.parse(zero).approximateLength, 200)
    }
}
#endif

#if canImport(SwiftUI)
/// Contrast is the reason these palettes were chosen, so it is checked here
/// rather than trusted from the web build.
final class ThemeTests: XCTestCase {
    /// WCAG relative luminance.
    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: Double) -> Double {
            let v = value / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = channel(Double((hex >> 16) & 0xff))
        let g = channel(Double((hex >> 8) & 0xff))
        let b = channel(Double(hex & 0xff))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testEveryAccentClearsAAOnItsOwnSurface() {
        // Each accent is checked against the surface it actually sits on, not a
        // generic background - that is what caught the brand red at 4.43:1.
        let pairs: [(String, UInt32, UInt32)] = [
            ("midnight", 0x101319, 0xee3240),
            ("ember", 0x17130f, 0xf5a524),
            ("abyss", 0x0e1420, 0x38bdf8),
            ("moss", 0x121711, 0xa3e635),
        ]
        for (name, surface, accent) in pairs {
            XCTAssertGreaterThanOrEqual(contrast(surface, accent), 4.5,
                                        "\(name) accent fails AA on its own surface")
        }
    }

    func testOriginalBrandRedWouldHaveFailed() {
        // Documents why the shipped accent is #ee3240 and not #ed2b3a.
        XCTAssertLessThan(contrast(0x101319, 0xed2b3a), 4.5)
    }

    func testThemeLookupFallsBackToMidnight() {
        XCTAssertEqual(VEXTheme.named("abyss").id, "abyss")
        XCTAssertEqual(VEXTheme.named("nonsense").id, "midnight")
        XCTAssertEqual(VEXTheme.named(nil).id, "midnight")
        XCTAssertEqual(VEXTheme.all.count, 4)
    }
}
#endif

final class EventDecodingTests: XCTestCase {
    private func events() throws -> [VEXEvent] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/events", withExtension: "json"))
        return try JSONDecoder().decode(EventsResponse.self, from: Data(contentsOf: url)).events
    }

    func testDecodesTheWholeLiveFeed() throws {
        let all = try events()
        XCTAssertGreaterThan(all.count, 500)
        XCTAssertFalse(all.contains { $0.name.isEmpty })
    }

    func testClassKeywordFieldIsMappedNotDropped() throws {
        // `class` is a Swift keyword; a silent mapping failure would leave every
        // value nil and nothing else would notice.
        let all = try events()
        XCTAssertTrue(all.contains { $0.eventClass != nil }, "no event carried a class value")
    }

    func testCalendarDayParsesAndUpcomingSplitsTheFeed() throws {
        let all = try events()
        XCTAssertTrue(all.allSatisfy { $0.day != nil }, "an event date failed to parse")
        let upcoming = all.filter(\.isUpcoming)
        XCTAssertGreaterThan(upcoming.count, 0)
        XCTAssertLessThan(upcoming.count, all.count, "feed should span past and future")
    }

    func testPlaceDoesNotRepeatComponents() throws {
        // city carries "City, Region" and eventRegion repeats the region, which
        // rendered as "Hamburg, Hamburg, Hamburg" before deduplication.
        for event in try events() {
            let parts = event.place.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            XCTAssertEqual(Set(parts).count, parts.count, "repeated component in \(event.place)")
        }
    }

    func testPlaceKeepsMostSpecificFirst() throws {
        let all = try events()
        let hamburg = all.first { $0.city == "Hamburg, Hamburg" }
        if let hamburg { XCTAssertEqual(hamburg.place, "Hamburg, Germany") }
        let auckland = all.first { $0.city == "Auckland, Auckland" }
        if let auckland { XCTAssertEqual(auckland.place, "Auckland, New Zealand") }
    }

    func testPlaceJoinsWhatIsPresentWithoutStrayCommas() throws {
        let all = try events()
        for event in all.prefix(200) {
            XCTAssertFalse(event.place.hasPrefix(", "), "leading comma in \(event.place)")
            XCTAssertFalse(event.place.hasSuffix(", "), "trailing comma in \(event.place)")
        }
    }
}

final class EventDetailTests: XCTestCase {
    private func detail() throws -> EventDetailResponse {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/event-detail", withExtension: "json"))
        return try JSONDecoder().decode(EventDetailResponse.self, from: Data(contentsOf: url))
    }

    func testDecodesACompletedEventWithResults() throws {
        let response = try detail()
        XCTAssertFalse(response.event.name.isEmpty)
        XCTAssertGreaterThan(response.teams.count, 10)
        XCTAssertGreaterThan(response.divisions.count, 0)
        XCTAssertGreaterThan(response.awards.count, 0)
    }

    func testDivisionRankingsAreOrderedAndFormatted() throws {
        let division = try XCTUnwrap(try detail().divisions.first)
        XCTAssertGreaterThan(division.rankings.count, 10)
        let sorted = division.rankings.sorted { $0.rank < $1.rank }
        let top = try XCTUnwrap(sorted.first)
        XCTAssertEqual(top.rank, 1)
        XCTAssertEqual(top.record, "\(top.wins)–\(top.losses)–\(top.ties)")
    }

    func testDivisionTeamCarriesTheNumberInItsNameField() throws {
        // The API puts the team number in `team.name`. If that ever changes the
        // event ranking list would show blanks, so it is pinned here.
        let division = try XCTUnwrap(try detail().divisions.first)
        for ranking in division.rankings.prefix(20) {
            XCTAssertFalse(ranking.team.name.isEmpty)
            XCTAssertTrue(ranking.team.name.contains(where: \.isNumber),
                          "expected a team number, got \(ranking.team.name)")
        }
    }

    func testVenueLineSkipsMissingParts() throws {
        let response = try detail()
        let line = response.event.venueLine
        XCTAssertFalse(line.contains(", ,"))
        XCTAssertFalse(line.hasPrefix(", "))
    }

    func testSkillsLeaderboardFoldsBothRunsPerTeam() throws {
        let response = try detail()
        let board = response.skillsLeaderboard
        XCTAssertFalse(board.isEmpty)
        // Two rows per team in the feed collapse to one row per team here.
        XCTAssertLessThan(board.count, response.skills.count)
        XCTAssertEqual(board.count, Set(board.map { $0.number }).count)
        for leader in board {
            XCTAssertEqual(leader.total, leader.driver + leader.programming)
        }
        for (a, b) in zip(board, board.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.total, b.total)
        }
    }

}

/// Stat leaders are computed on-device from two feeds, so the arithmetic and
/// the qualification thresholds - not just decoding - are what these cover.
final class StatLeaderTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func teams() throws -> [TeamRanking] {
        try JSONDecoder().decode(RankingsResponse.self, from: fixture("rankings")).rankings
    }

    private func skills() throws -> [SkillsEntry] {
        try JSONDecoder().decode(SkillsResponse.self, from: fixture("skills")).rankings
    }

    func testDecodesLiveSkillsResponse() throws {
        let entries = try skills()
        XCTAssertGreaterThan(entries.count, 100)
        let leader = try XCTUnwrap(entries.first)
        XCTAssertEqual(leader.skillsRank, 1)
        XCTAssertEqual(leader.autoSkills + leader.driverSkills, leader.combinedSkills)
    }

    func testWinRateCountsTiesAsHalf() {
        XCTAssertEqual(StatLeaders.winRate(record: "6\u{2013}2\u{2013}2", matches: 10), 70, accuracy: 0.001)
        XCTAssertEqual(StatLeaders.winRate(record: "6-2-2", matches: 10), 70, accuracy: 0.001)
        // A record the API stopped sending, or zero matches, must not divide by
        // zero or crash the whole leaderboard.
        XCTAssertEqual(StatLeaders.winRate(record: nil, matches: 10), 0)
        XCTAssertEqual(StatLeaders.winRate(record: "6\u{2013}2\u{2013}2", matches: 0), 0)
    }

    func testScoresStayInsideZeroToOneHundred() throws {
        for team in try teams() {
            let picking = StatLeaders.pickingScore(team)
            XCTAssertTrue((0...100).contains(picking), "picking \(picking) for \(team.number)")
            let consistency = StatLeaders.consistencyScore(team)
            XCTAssertTrue((0...100).contains(consistency), "consistency \(consistency) for \(team.number)")
        }
    }

    func testEveryCategoryIsSortedBestFirst() throws {
        let teams = try teams()
        let skills = try skills()
        for category in StatCategory.all {
            let rows = StatLeaders.rank(category: category, teams: teams, skills: skills)
            XCTAssertFalse(rows.isEmpty, "\(category.id) produced no rows")
            for (a, b) in zip(rows, rows.dropFirst()) {
                if category.lowerIsBetter {
                    XCTAssertLessThanOrEqual(a.value, b.value, "\(category.id) out of order")
                } else {
                    XCTAssertGreaterThanOrEqual(a.value, b.value, "\(category.id) out of order")
                }
            }
        }
    }

    func testMatchCategoriesEnforceTheirThresholds() throws {
        let teams = try teams()
        let skills = try skills()
        let byNumber = Dictionary(teams.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })

        let offense = StatLeaders.rank(category: StatCategory.all[0], teams: teams, skills: skills)
        for row in offense {
            XCTAssertGreaterThanOrEqual(byNumber[row.number]?.matches ?? 0, 12)
        }

        let picking = StatLeaders.rank(category: StatCategory.all[2], teams: teams, skills: skills)
        for row in picking {
            let team = try XCTUnwrap(byNumber[row.number])
            XCTAssertGreaterThanOrEqual(team.matches ?? 0, 36)
            XCTAssertGreaterThanOrEqual(team.events, 4)
        }
        // The stricter threshold has to actually exclude teams, or it is not
        // doing the job the copy claims.
        XCTAssertLessThan(picking.count, offense.count)
    }

    func testCountryFilterNarrowsTheField() throws {
        let teams = try teams()
        let skills = try skills()
        let category = StatCategory.all[0]
        let all = StatLeaders.rank(category: category, teams: teams, skills: skills)
        let country = try XCTUnwrap(StatLeaders.countries(category: category, teams: teams, skills: skills).first)
        let filtered = StatLeaders.rank(category: category, teams: teams, skills: skills, country: country)
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertLessThan(filtered.count, all.count)
    }

    func testSkillsRowsDoNotOfferAProfile() throws {
        let rows = StatLeaders.rank(category: StatCategory.all[6], teams: try teams(), skills: try skills())
        XCTAssertFalse(rows.contains { $0.opensProfile })
        XCTAssertTrue(StatLeaders.rank(category: StatCategory.all[0], teams: try teams(), skills: try skills()).allSatisfy(\.opensProfile))
    }
}
