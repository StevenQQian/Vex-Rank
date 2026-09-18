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

/// The growing rating curve is the animation's data, so its arithmetic is
/// testable even though the drawing is not.
final class RatingCurveTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func history() throws -> [RatingPoint] {
        try JSONDecoder().decode(TeamProfileResponse.self, from: fixture("team")).ratingHistory
    }

    func testStartsFromNothingAndEndsComplete() throws {
        let history = try history()
        XCTAssertTrue(RatingCurve.growing(history, progress: 0).isEmpty,
                      "the curve must grow from none, not from a stray first point")
        let full = RatingCurve.growing(history, progress: 1)
        XCTAssertEqual(full.count, history.compactMap(\.date).count)
        XCTAssertTrue(full.allSatisfy(\.isEvent))
    }

    func testGrowsMonotonicallyAndNeverOvershoots() throws {
        let history = try history()
        var previous = 0
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let samples = RatingCurve.growing(history, progress: step)
            XCTAssertGreaterThanOrEqual(samples.count, previous)
            previous = samples.count
            // Out-of-range progress must clamp rather than trap on a bad index.
            XCTAssertLessThanOrEqual(samples.count, history.count)
        }
        XCTAssertEqual(RatingCurve.growing(history, progress: 4).count,
                       RatingCurve.growing(history, progress: 1).count)
        XCTAssertTrue(RatingCurve.growing(history, progress: -3).isEmpty)
    }

    func testMovingTipIsInterpolatedAndNotMarkedAnEvent() throws {
        let history = try history()
        let dated = history.compactMap { point in point.date.map { ($0, Double(point.rating)) } }
            .sorted { $0.0 < $1.0 }
        // Halfway along the first segment of the series.
        let step = 0.5 / Double(dated.count - 1)
        let samples = RatingCurve.growing(history, progress: step)
        let tip = try XCTUnwrap(samples.last)
        XCTAssertFalse(tip.isEvent)
        XCTAssertEqual(tip.rating, (dated[0].1 + dated[1].1) / 2, accuracy: 0.001)
        XCTAssertTrue(samples.dropLast().allSatisfy(\.isEvent))
    }

    func testDomainsCoverTheWholeSeriesSoAxesDoNotMove() throws {
        let history = try history()
        let ratings = history.map { Double($0.rating) }
        let domain = RatingCurve.ratingDomain(history)
        XCTAssertLessThan(domain.lowerBound, ratings.min()!)
        XCTAssertGreaterThan(domain.upperBound, ratings.max()!)

        // The x domain is in event positions, and is padded so the first and
        // last dots are not cut in half by the edge of the plot.
        let events = RatingCurve.ordered(history)
        let x = RatingCurve.eventDomain(history)
        XCTAssertLessThan(x.lowerBound, 0)
        XCTAssertGreaterThan(x.upperBound, Double(events.count - 1))
    }

    func testEventsAreSpacedEvenlyRatherThanByDate() throws {
        let history = try history()
        let samples = RatingCurve.growing(history, progress: 1)
        // Equal spacing is what keeps a cluster of events from being drawn as
        // a vertical spike, which is how the date-scaled version looked.
        for (index, sample) in samples.enumerated() {
            XCTAssertEqual(sample.x, Double(index), accuracy: 0.0001)
        }
        XCTAssertEqual(samples.map(\.change), RatingCurve.ordered(history).map(\.change))
    }

    func testAxisLabelsStayInRangeAndReadable() throws {
        let history = try history()
        let labels = RatingCurve.axisLabels(history)
        XCTAssertFalse(labels.isEmpty)
        XCTAssertLessThanOrEqual(labels.count, RatingCurve.ordered(history).count)
        for label in labels {
            XCTAssertGreaterThanOrEqual(label.x, 0)
            XCTAssertLessThan(label.x, Double(RatingCurve.ordered(history).count))
            XCTAssertFalse(label.label.isEmpty)
        }
        // Strictly increasing, so two labels never land on the same tick.
        XCTAssertEqual(labels.map(\.x), labels.map(\.x).sorted())
        XCTAssertEqual(Set(labels.map(\.x)).count, labels.count)
    }

    func testLabelsCarryTheYearWhenTheSeriesCrossesOne() throws {
        let events = RatingCurve.ordered(try history())
        let calendar = Calendar.current
        let years = Set(events.map { calendar.component(.year, from: $0.date) })
        let labels = RatingCurve.axisLabels(try history())
        guard years.count > 1 else {
            throw XCTSkip("this fixture's history sits inside one calendar year")
        }
        // Otherwise the labels read as out of order: "Jul 1, Nov 15, Sep 12".
        for label in labels {
            XCTAssertTrue(years.contains { label.label.contains(String($0)) },
                          "expected a year in \(label.label)")
        }
    }

    func testEasingIsClampedAndEndsWhereItShould() {
        XCTAssertEqual(RatingCurve.eased(0), 0, accuracy: 0.0001)
        XCTAssertEqual(RatingCurve.eased(1), 1, accuracy: 0.0001)
        XCTAssertEqual(RatingCurve.eased(9), 1, accuracy: 0.0001)
        XCTAssertEqual(RatingCurve.eased(-9), 0, accuracy: 0.0001)
        // Ease-out: more than half the distance covered in the first half.
        XCTAssertGreaterThan(RatingCurve.eased(0.5), 0.5)
    }
}

/// The season-scoped parts of a team profile: the picker's seasons, the
/// per-event standings and the skills bests.
final class TeamSeasonTests: XCTestCase {
    private func profile() throws -> TeamProfileResponse {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/team", withExtension: "json"))
        return try JSONDecoder().decode(TeamProfileResponse.self, from: Data(contentsOf: url))
    }

    func testDecodesEventsStandingsAndGrades() throws {
        let profile = try profile()
        XCTAssertFalse(try XCTUnwrap(profile.events).isEmpty)
        XCTAssertFalse(try XCTUnwrap(profile.rankings).isEmpty)
        XCTAssertFalse(try XCTUnwrap(profile.seasonGrades).isEmpty)

        let standing = try XCTUnwrap(profile.rankings?.first)
        XCTAssertEqual(standing.record, "\(standing.wins)\u{2013}\(standing.losses)\u{2013}\(standing.ties)")
    }

    func testSeasonsAreNewestFirstAndUnique() throws {
        let seasons = try profile().seasons
        XCTAssertGreaterThan(seasons.count, 1, "this fixture spans more than one season")
        XCTAssertEqual(seasons.map(\.id), seasons.map(\.id).sorted(by: >))
        XCTAssertEqual(Set(seasons.map(\.id)).count, seasons.count)
    }

    func testSeasonNameIsShortenedForThePicker() throws {
        // "VEX V5 Robotics Competition 2026-2027: Override" is too long for a
        // picker row; the reader only needs the years and the game.
        let season = try XCTUnwrap(profile().seasons.first)
        XCTAssertEqual(season.shortName, "2026\u{2013}27 Override")
    }

    func testGradeIsReadPerSeason() throws {
        let profile = try profile()
        for season in profile.seasons {
            XCTAssertFalse(profile.grade(forSeason: season.id).isEmpty)
        }
        // An unknown season falls back to the identity rather than going blank.
        XCTAssertEqual(profile.grade(forSeason: -1), profile.team.grade)
    }

    func testCombinedSkillsComeFromOneEventNotTwo() throws {
        let runs = try XCTUnwrap(profile().skills)
        let best = SeasonSkills(runs: runs)
        XCTAssertGreaterThan(best.combined, 0)
        // The official standing is the best pair at a single event, so it can
        // never beat adding the two season bests together.
        XCTAssertLessThanOrEqual(best.combined, best.driver + best.programming)
        XCTAssertGreaterThanOrEqual(best.combined, max(best.driver, best.programming))
    }

    func testPlaceholderEliminationResultIsTreatedAsAbsent() throws {
        let events = try XCTUnwrap(profile().events)
        // The API writes "No elimination result" instead of omitting the field,
        // which would otherwise be printed to the reader as if it were one.
        for event in events where event.elimination?.localizedCaseInsensitiveContains("no elimination") == true {
            XCTAssertNil(event.eliminationResult)
        }
    }
}

/// The ranking filters, against the live feed.
final class RankingFilterTests: XCTestCase {
    private func teams() throws -> [TeamRanking] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/rankings", withExtension: "json"))
        return try JSONDecoder().decode(RankingsResponse.self, from: Data(contentsOf: url)).rankings
    }

    func testRegionUsesTheEventRegionAndOtherwiseTheFirstComponent() {
        let base = try? teams().first
        XCTAssertNotNil(base)
        // A full "Victoria, Australia" must reduce to "Victoria", or every team
        // ends up in a region of its own.
        let teams = try! teams()
        for team in teams.prefix(50) {
            guard let region = RankingFilter.regionOf(team) else { continue }
            XCTAssertFalse(region.contains(","), "expected one component, got \(region)")
            XCTAssertFalse(region.hasPrefix(" "))
        }
    }

    func testEachFilterNarrowsTheField() throws {
        let teams = try teams()
        let all = RankingFilter().apply(to: teams)
        XCTAssertEqual(all.count, teams.count, "an empty filter must not drop anyone")

        let country = try XCTUnwrap(RankingFilter.countries(teams).first)
        let byCountry = RankingFilter(country: country).apply(to: teams)
        XCTAssertFalse(byCountry.isEmpty)
        XCTAssertLessThan(byCountry.count, teams.count)
        XCTAssertTrue(byCountry.allSatisfy { $0.country == country })

        let region = try XCTUnwrap(RankingFilter.regions(teams, country: country).first)
        let byRegion = RankingFilter(country: country, region: region).apply(to: teams)
        XCTAssertFalse(byRegion.isEmpty)
        XCTAssertLessThanOrEqual(byRegion.count, byCountry.count)
    }

    func testRegionsAreScopedToTheChosenCountry() throws {
        let teams = try teams()
        let country = try XCTUnwrap(RankingFilter.countries(teams).first)
        let scoped = RankingFilter.regions(teams, country: country)
        let everywhere = RankingFilter.regions(teams, country: nil)
        XCTAssertFalse(scoped.isEmpty)
        XCTAssertLessThan(scoped.count, everywhere.count)
        // Every scoped region must actually contain teams from that country.
        for region in scoped {
            XCTAssertFalse(RankingFilter(country: country, region: region).apply(to: teams).isEmpty)
        }
    }

    func testGradeAndSearchCombine() throws {
        let teams = try teams()
        let highSchool = RankingFilter(grade: .highSchool).apply(to: teams)
        XCTAssertTrue(highSchool.allSatisfy { $0.grade == "High School" })

        let leader = try XCTUnwrap(teams.first)
        let found = RankingFilter(search: leader.number.lowercased()).apply(to: teams)
        XCTAssertTrue(found.contains { $0.number == leader.number })
        XCTAssertTrue(RankingFilter(search: "   ").apply(to: teams).count == teams.count,
                      "whitespace is not a search")
    }
}

/// Match lists, which the event screen shows and the web orders by a bracket
/// that the API's round numbers do not follow.
final class EventMatchTests: XCTestCase {
    private func detail() throws -> EventDetailResponse {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/event-detail", withExtension: "json"))
        return try JSONDecoder().decode(EventDetailResponse.self, from: Data(contentsOf: url))
    }

    private func division() throws -> Division {
        try XCTUnwrap(detail().divisions.first)
    }

    func testDecodesAlliancesAndScores() throws {
        let match = try XCTUnwrap(division().qualification.first)
        XCTAssertEqual(match.red?.numbers.count, 2)
        XCTAssertEqual(match.blue?.numbers.count, 2)
        XCTAssertNotNil(match.red?.score)
        XCTAssertFalse(try XCTUnwrap(match.red?.numbers.first).isEmpty)
    }

    func testPlayedIsReadFromTheScoreNotTheScoredFlag() throws {
        let division = try division()
        let scoredFlagged = division.qualification.filter { $0.isPlayed }
        XCTAssertFalse(scoredFlagged.isEmpty, "this event was played")
        // The captured payload reports scored: false on matches that carry a
        // real result, so the flag cannot be what decides this.
        let raw = try XCTUnwrap(division.qualification.first { $0.isPlayed })
        XCTAssertGreaterThan(try XCTUnwrap(raw.red?.score) + (raw.blue?.score ?? 0), 0)
    }

    func testWinnerIsTheHigherScoreAndNilOnATie() throws {
        for match in try division().qualification where match.isPlayed {
            let red = try XCTUnwrap(match.red?.score)
            let blue = try XCTUnwrap(match.blue?.score)
            if red == blue {
                XCTAssertNil(match.winner)
            } else {
                XCTAssertEqual(match.winner, red > blue ? "red" : "blue")
            }
        }
    }

    func testQualificationAndEliminationDoNotOverlap() throws {
        let division = try division()
        let qualification = Set(division.qualification.map(\.id))
        let elimination = Set(division.elimination.map(\.id))
        XCTAssertFalse(qualification.isEmpty)
        XCTAssertFalse(elimination.isEmpty)
        XCTAssertTrue(qualification.isDisjoint(with: elimination))
        XCTAssertEqual(qualification.count + elimination.count, division.matches?.count)
    }

    func testRoundOfSixteenSortsBeforeTheQuarterFinals() throws {
        let rounds = try division().elimination.compactMap(\.round)
        // The API numbers the round of 16 as 6, above the quarter-finals at 3,
        // so a plain sort on the round would run the bracket backwards.
        XCTAssertEqual(rounds.first, 6)
        XCTAssertEqual(rounds.last, 5)
        XCTAssertEqual(rounds, rounds.sorted { Division.bracketOrder($0) < Division.bracketOrder($1) })
    }

    func testQualificationIsInPlayOrder() throws {
        let numbers = try division().qualification.compactMap(\.matchnum)
        XCTAssertEqual(numbers, numbers.sorted())
    }
}

/// The team directory's search rules, against a subset of the live feed: the
/// first 300 teams plus every member of two numeric families, so the family
/// behaviour is exercised on real rows rather than invented ones.
final class TeamDirectoryTests: XCTestCase {
    private func directory() throws -> [DirectoryTeam] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/team-directory", withExtension: "json"))
        return try JSONDecoder().decode(TeamDirectoryResponse.self, from: Data(contentsOf: url)).teams
    }

    private func indexed() throws -> [(team: DirectoryTeam, haystack: String)] {
        try directory().map { ($0, TeamDirectory.haystack($0)) }
    }

    func testDecodesTheLiveDirectory() throws {
        let teams = try directory()
        XCTAssertGreaterThan(teams.count, 100)
        XCTAssertTrue(teams.contains { $0.registered == false }, "a directory includes historical teams")
        XCTAssertFalse(try XCTUnwrap(teams.first).number.isEmpty)
    }

    func testANumberFindsItsWholeFamily() throws {
        let family = TeamDirectory.search(try indexed(), query: "2011")
        XCTAssertGreaterThan(family.count, 1)
        XCTAssertTrue(family.allSatisfy { $0.number.lowercased().contains("2011")
            || TeamDirectory.haystack($0).contains("2011") })
        // And the suffix narrows it back down to one.
        let one = TeamDirectory.search(try indexed(), query: " 2011a ")
        XCTAssertEqual(one.first?.number.lowercased(), "2011a")
    }

    func testExactNumberOutranksAPrefixAndAName() throws {
        let results = TeamDirectory.search(try indexed(), query: "2011a")
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.number.lowercased(), "2011a")
        XCTAssertEqual(TeamDirectory.priority("2011A", "2011a"), 0)
        XCTAssertEqual(TeamDirectory.priority("2011AB", "2011a"), 1)
        XCTAssertEqual(TeamDirectory.priority("9999Z", "2011a"), 2)
    }

    func testResultsAreInNaturalNumericOrder() throws {
        let all = TeamDirectory.search(try indexed(), query: "")
        let numbers = all.prefix(40).map(\.number)
        // "2A" must come before "2011A": a plain string sort puts 2011 first.
        XCTAssertEqual(numbers, numbers.sorted {
            $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending
        })
    }

    func testEveryTokenMustMatch() throws {
        let indexed = try indexed()
        let team = try XCTUnwrap(indexed.first { ($0.team.organization?.isEmpty == false) }).team
        let organization = try XCTUnwrap(team.organization)
        let both = TeamDirectory.search(indexed, query: "\(team.number) \(organization)")
        XCTAssertTrue(both.contains { $0.id == team.id })
        // A token that matches nothing empties the result rather than widening.
        XCTAssertTrue(TeamDirectory.search(indexed, query: "\(team.number) zzzznotathing").isEmpty)
    }

    func testCountriesNormalizeBeforeTheyGroup() throws {
        XCTAssertEqual(TeamDirectory.normalizeCountry("USA"), "United States")
        XCTAssertEqual(TeamDirectory.normalizeCountry("us"), "United States")
        XCTAssertEqual(TeamDirectory.normalizeCountry("United States of America"), "United States")
        XCTAssertEqual(TeamDirectory.normalizeCountry("Canada"), "Canada")
        XCTAssertEqual(TeamDirectory.normalizeCountry(nil), "Unassigned")

        let countries = TeamDirectory.locations(try directory()).countries
        XCTAssertEqual(Set(countries).count, countries.count)
        XCTAssertFalse(countries.contains("USA"))
    }

    func testRegionsAreScopedToTheCountry() throws {
        let teams = try directory()
        let country = try XCTUnwrap(TeamDirectory.locations(teams).countries.first)
        let scoped = TeamDirectory.locations(teams, country: country).regions
        XCTAssertFalse(scoped.isEmpty)
        for region in scoped {
            let rows = TeamDirectory.search(try indexed(), query: "",
                                            filters: .init(country: country, region: region))
            XCTAssertFalse(rows.isEmpty, "\(region) in \(country) listed but empty")
        }
    }

    func testFiltersCombine() throws {
        let indexed = try indexed()
        let all = TeamDirectory.search(indexed, query: "")
        let country = try XCTUnwrap(TeamDirectory.locations(try directory()).countries.first)
        let byCountry = TeamDirectory.search(indexed, query: "", filters: .init(country: country))
        XCTAssertFalse(byCountry.isEmpty)
        XCTAssertLessThan(byCountry.count, all.count)

        let grade = try XCTUnwrap(byCountry.compactMap(\.grade).first)
        let both = TeamDirectory.search(indexed, query: "", filters: .init(country: country, grade: grade))
        XCTAssertTrue(both.allSatisfy { $0.grade == grade })
        XCTAssertLessThanOrEqual(both.count, byCountry.count)
    }
}

extension TeamDirectoryTests {
    func testAsOfParsesDespiteFractionalSeconds() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/team-directory", withExtension: "json"))
        let response = try JSONDecoder().decode(TeamDirectoryResponse.self, from: Data(contentsOf: url))
        // The feed writes milliseconds; the default parser rejects them and the
        // "updated" line silently disappeared.
        XCTAssertTrue(response.asOf.contains("."), "this fixture should carry fractional seconds")
        XCTAssertNotNil(response.updated)
    }
}

/// The elimination bracket. The captured event is a useful case: its round of
/// 16 has nine matches for eight slots, so replay handling is exercised for
/// real rather than hypothetically.
final class BracketTests: XCTestCase {
    private func division() throws -> Division {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/event-detail", withExtension: "json"))
        let detail = try JSONDecoder().decode(EventDetailResponse.self, from: Data(contentsOf: url))
        return try XCTUnwrap(detail.divisions.first)
    }

    func testRoundsAreEarliestFirstWithFixedSlotCounts() throws {
        let rounds = try division().bracket
        XCTAssertEqual(rounds.map(\.label), ["Round of 16", "Quarterfinals", "Semifinals"])
        XCTAssertEqual(rounds.map { $0.slots.count }, [8, 4, 2])
    }

    func testAReplayStaysInItsOwnSlot() throws {
        let rounds = try division().bracket
        let roundOf16 = try XCTUnwrap(rounds.first)
        let matches = try division().elimination.filter { $0.round == 6 }
        XCTAssertEqual(matches.count, 9, "this event replayed one match")
        // Nine matches, still eight slots: the replay shares a slot rather than
        // inventing a ninth opponent and shifting the bracket.
        XCTAssertEqual(roundOf16.slots.count, 8)
        XCTAssertEqual(roundOf16.played, 8)
        let replayed = try XCTUnwrap(roundOf16.slots.compactMap { $0 }.first { $0.wasReplayed })
        XCTAssertEqual(replayed.games.count, 2)
        // The card shows the last game played, not the first.
        XCTAssertEqual(replayed.match.matchnum, replayed.games.map(\.matchnum).compactMap { $0 }.max())
    }

    func testEverySlotHoldsItsOwnInstance() throws {
        for round in try division().bracket {
            for (index, slot) in round.slots.enumerated() {
                guard let slot else { continue }
                XCTAssertEqual(slot.instance, index + 1)
                XCTAssertTrue(slot.games.allSatisfy { $0.round == round.id && $0.instance == slot.instance })
            }
        }
    }

    func testFinalSeriesIsCountedByAllianceNotByColour() throws {
        let final = try XCTUnwrap(try division().final)
        XCTAssertFalse(final.red.isEmpty)
        XCTAssertFalse(final.blue.isEmpty)
        XCTAssertEqual(final.redWins + final.blueWins, final.games.filter { $0.winner != nil }.count)
        // A decided series has a winner on two, and the winner holds the most.
        if let winner = final.winner {
            XCTAssertGreaterThanOrEqual(max(final.redWins, final.blueWins), 2)
            XCTAssertEqual(winner, final.redWins > final.blueWins ? "red" : "blue")
        } else {
            XCTAssertTrue(max(final.redWins, final.blueWins) < 2 || final.redWins == final.blueWins)
        }
    }

    func testAllianceKeyIgnoresOrderAndCase() {
        XCTAssertEqual(Division.allianceKey(["19600Z", "11111y"]),
                       Division.allianceKey(["11111Y", "19600z"]))
        XCTAssertNotEqual(Division.allianceKey(["19600Z"]), Division.allianceKey(["19600X"]))
    }

    func testBracketAndFinalDoNotShareMatches() throws {
        let division = try division()
        let inRounds = Set(division.bracket.flatMap { $0.slots.compactMap { $0 }.flatMap { $0.games }.map(\.id) })
        let inFinal = Set((division.final?.games ?? []).map(\.id))
        XCTAssertFalse(inRounds.isEmpty)
        XCTAssertFalse(inFinal.isEmpty)
        XCTAssertTrue(inRounds.isDisjoint(with: inFinal))
        XCTAssertEqual(inRounds.count + inFinal.count, division.elimination.count)
    }
}

/// Team numbers are not ordinary strings, and every list of them sorts the
/// same way.
final class TeamNumberOrderTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    func testDigitsCompareAsNumbersNotAsText() {
        // The bug this replaces: "10188S" sorted above "2731K" because a string
        // comparison reaches 0 against 7 and stops.
        XCTAssertTrue(TeamNumber.precedes("2731K", "10188S"))
        XCTAssertFalse(TeamNumber.precedes("10188S", "2731K"))
        XCTAssertTrue(TeamNumber.precedes("2A", "2011A"))
        XCTAssertTrue(TeamNumber.precedes("2011A", "2011B"))
        XCTAssertTrue(TeamNumber.same("2011a", "2011A"))
        XCTAssertFalse(TeamNumber.same("2011A", "2011B"))
    }

    func testRegisteredTeamsAtAnEventAreInNumericOrder() throws {
        let detail = try fixture("event-detail", as: EventDetailResponse.self)
        let sorted = detail.teams.sorted { TeamNumber.precedes($0.number, $1.number) }
        XCTAssertGreaterThan(sorted.count, 10)
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertTrue(TeamNumber.precedes(a.number, b.number) || TeamNumber.same(a.number, b.number),
                          "\(a.number) should not precede \(b.number)")
        }
        // And the order really does differ from a plain string sort on this
        // event, so the test would fail against the old behaviour.
        XCTAssertNotEqual(sorted.map(\.number), detail.teams.map(\.number).sorted())
    }

    func testRankingTiesBreakNumerically() throws {
        let response = try fixture("rankings", as: RankingsResponse.self)
        let display = response.sortedForDisplay
        for (a, b) in zip(display, display.dropFirst()) where a.rank == b.rank {
            XCTAssertTrue(TeamNumber.precedes(a.number, b.number))
        }
    }

    func testStatLeaderTiesBreakNumerically() throws {
        let teams = try fixture("rankings", as: RankingsResponse.self).rankings
        let skills = try fixture("skills", as: SkillsResponse.self).rankings
        for category in StatCategory.all {
            let rows = StatLeaders.rank(category: category, teams: teams, skills: skills)
            for (a, b) in zip(rows, rows.dropFirst()) where a.value == b.value {
                XCTAssertTrue(TeamNumber.precedes(a.number, b.number),
                              "\(category.id): \(a.number) before \(b.number)")
            }
        }
    }
}

/// A team's remaining schedule at the competition it is at now.
///
/// Both fixtures were captured while an event was actually running - a
/// three-day signature event with 219 scheduled matches and none yet played -
/// which is the only state in which this feature does anything.
final class UpcomingMatchTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func profile() throws -> TeamProfileResponse { try fixture("team-live", as: TeamProfileResponse.self) }
    private func event() throws -> EventDetailResponse { try fixture("event-live", as: EventDetailResponse.self) }

    /// A day inside the captured event's run (18-20 September 2026).
    private func day(_ day: Int) -> Date {
        DateComponents(calendar: .current, timeZone: .current,
                       year: 2026, month: 9, day: day, hour: 12).date!
    }

    func testFindsTheEventTheTeamIsAtToday() throws {
        let current = try XCTUnwrap(profile().currentEvent(on: day(18)))
        XCTAssertEqual(current.id, 64359)
        // Every day of a multi-day event counts, not just the first.
        XCTAssertEqual(try profile().currentEvent(on: day(19))?.id, 64359)
        XCTAssertEqual(try profile().currentEvent(on: day(20))?.id, 64359)
    }

    func testNoEventOnDaysOutsideTheRun() throws {
        XCTAssertNil(try profile().currentEvent(on: day(17)))
        XCTAssertNil(try profile().currentEvent(on: day(21)))
    }

    func testEventRunIsComparedByDayNotByInstant() throws {
        let event = try XCTUnwrap(profile().events?.first { $0.id == 64359 })
        // Timestamps are midnight in the venue's offset. Comparing instants
        // would end the event part-way through its last day for a reader in
        // another time zone.
        XCTAssertTrue(event.runs(on: day(20)))
        let lateOnTheLastDay = DateComponents(calendar: .current, timeZone: .current,
                                              year: 2026, month: 9, day: 20, hour: 23).date!
        XCTAssertTrue(event.runs(on: lateOnTheLastDay))
    }

    func testListsOnlyThisTeamsUnplayedMatches() throws {
        let matches = try event().upcomingMatches(for: "663D")
        XCTAssertFalse(matches.isEmpty)
        let all = try event().divisions.flatMap { $0.matches ?? [] }
        XCTAssertLessThan(matches.count, all.count, "one team does not play every match")

        for match in matches {
            let source = try XCTUnwrap(all.first { $0.id == match.id })
            XCTAssertFalse(source.isPlayed)
            let mine = match.colour == "red" ? source.red : source.blue
            XCTAssertTrue(mine?.numbers.contains { $0.uppercased() == "663D" } ?? false)
            // The team is not listed as its own partner or its own opponent.
            XCTAssertFalse(match.partners.contains { $0.uppercased() == "663D" })
            XCTAssertFalse(match.opponents.contains { $0.uppercased() == "663D" })
        }
    }

    func testMatchingIsCaseInsensitive() throws {
        XCTAssertEqual(try event().upcomingMatches(for: "663d").map(\.id),
                       try event().upcomingMatches(for: "663D").map(\.id))
    }

    func testAreInScheduledOrder() throws {
        let matches = try event().upcomingMatches(for: "663D")
        let times = matches.compactMap(\.scheduled)
        XCTAssertEqual(times.count, matches.count, "this event schedules every match")
        XCTAssertEqual(times, times.sorted())
    }

    func testATeamNotAtTheEventHasNothing() throws {
        XCTAssertTrue(try event().upcomingMatches(for: "31260X").isEmpty)
    }

    func testAFinishedEventLeavesNothingToShow() throws {
        // The completed event: every match played, so nothing is upcoming even
        // for a team that was there.
        let finished = try fixture("event-detail", as: EventDetailResponse.self)
        let played = try XCTUnwrap(finished.divisions.first?.rankings.first?.team.name)
        XCTAssertTrue(finished.upcomingMatches(for: played).isEmpty)
    }
}

/// A team's matches at one event, read from that team's side.
final class TeamEventMatchTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// The completed event, where results exist to be read.
    private func finished() throws -> EventDetailResponse {
        try fixture("event-detail", as: EventDetailResponse.self)
    }

    private func aTeamThatPlayed() throws -> String {
        try XCTUnwrap(finished().divisions.first?.rankings.first?.team.name)
    }

    func testScoresAreOrientedToTheTeam() throws {
        let team = try aTeamThatPlayed()
        let matches = try finished().matches(for: team)
        XCTAssertFalse(matches.isEmpty)

        let raw = try XCTUnwrap(finished().divisions.first?.matches)
        for match in matches where match.isPlayed {
            let source = try XCTUnwrap(raw.first { $0.id == match.id })
            let mine = match.colour == "red" ? source.red?.score : source.blue?.score
            let theirs = match.colour == "red" ? source.blue?.score : source.red?.score
            // "For" is always this team's score whichever side they were on.
            XCTAssertEqual(match.scoreFor, mine)
            XCTAssertEqual(match.scoreAgainst, theirs)
        }
    }

    func testOutcomeFollowsTheScores() throws {
        for match in try finished().matches(for: try aTeamThatPlayed()) {
            guard match.isPlayed, let mine = match.scoreFor, let theirs = match.scoreAgainst else {
                XCTAssertEqual(match.outcome, .scheduled)
                continue
            }
            XCTAssertEqual(match.outcome, mine > theirs ? .won : mine < theirs ? .lost : .tied)
        }
    }

    func testAnUnplayedMatchCarriesNoScore() throws {
        let live = try fixture("event-live", as: EventDetailResponse.self)
        let matches = live.matches(for: "663D")
        XCTAssertFalse(matches.isEmpty)
        // The feed sends 0 against 0 for a fixture; reading that as a score
        // would print every upcoming match as a nil-all draw.
        for match in matches {
            XCTAssertFalse(match.isPlayed)
            XCTAssertNil(match.scoreFor)
            XCTAssertNil(match.scoreAgainst)
            XCTAssertEqual(match.outcome, .scheduled)
        }
    }

    func testRecordCountsWhatWasPlayedAndWhatIsLeft() throws {
        let team = try aTeamThatPlayed()
        let matches = try finished().matches(for: team)
        let record = TeamEventRecord(matches: matches)
        XCTAssertEqual(record.played, matches.filter(\.isPlayed).count)
        XCTAssertEqual(record.remaining, matches.filter { !$0.isPlayed }.count)
        XCTAssertEqual(record.wins + record.losses + record.ties, record.played)
        XCTAssertEqual(record.summary, "\(record.wins)\u{2013}\(record.losses)\u{2013}\(record.ties)")

        // At the live event nothing has been played, so it is all remaining.
        let live = TeamEventRecord(matches: try fixture("event-live", as: EventDetailResponse.self)
            .matches(for: "663D"))
        XCTAssertEqual(live.played, 0)
        XCTAssertGreaterThan(live.remaining, 0)
    }

    func testUpcomingIsTheUnplayedPartOfTheSameList() throws {
        let live = try fixture("event-live", as: EventDetailResponse.self)
        XCTAssertEqual(live.upcomingMatches(for: "663D").map(\.id),
                       live.matches(for: "663D").filter { !$0.isPlayed }.map(\.id))
        // A finished event has a history but nothing upcoming.
        let team = try aTeamThatPlayed()
        XCTAssertFalse(try finished().matches(for: team).isEmpty)
        XCTAssertTrue(try finished().upcomingMatches(for: team).isEmpty)
    }

    func testFocusIsCarriedOnTheEventReference() {
        let plain = EventRef(id: "1", name: "Event", day: nil, place: "", isUpcoming: false)
        XCTAssertNil(plain.focusTeam)
        XCTAssertEqual(plain.focused(on: "663D").focusTeam, "663D")
        // Focus is part of identity, so the two are different destinations.
        XCTAssertNotEqual(plain, plain.focused(on: "663D"))
    }
}

/// How an event screen organises itself, against a two-division event that
/// also carries a final-only division.
final class EventSectionTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func multi() throws -> EventDetailResponse {
        try fixture("event-multi", as: EventDetailResponse.self)
    }

    func testTheFixtureReallyHasSeveralDivisions() throws {
        let names = try multi().divisions.map(\.name)
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(names.contains { $0.localizedCaseInsensitiveContains("final") })
    }

    func testAFinalOnlyDivisionIsNotOfferedUnderRankings() throws {
        let detail = try multi()
        let standings = detail.divisions(for: .rankings)
        XCTAssertEqual(standings.count, 2, "only the two playing divisions have standings")
        XCTAssertFalse(standings.contains { $0.name.localizedCaseInsensitiveContains("final") })
        // It does hold matches, so it belongs under the bracket and matches.
        XCTAssertEqual(detail.divisions(for: .matches).count, 3)
        XCTAssertTrue(detail.divisions(for: .bracket).contains { $0.name.localizedCaseInsensitiveContains("final") })
    }

    func testEveryOfferedDivisionHasSomethingToShow() throws {
        let detail = try multi()
        for section in EventSection.allCases where section.isPerDivision {
            for division in detail.divisions(for: section) {
                switch section {
                case .rankings: XCTAssertFalse(division.rankings.isEmpty)
                case .bracket: XCTAssertFalse(division.elimination.isEmpty)
                case .matches: XCTAssertFalse((division.matches ?? []).isEmpty)
                default: break
                }
            }
        }
    }

    func testOnlySectionsWithContentAreOffered() throws {
        let sections = try multi().availableSections
        XCTAssertEqual(sections, [.rankings, .bracket, .matches, .awards, .skills, .teams])
        // Order is stable, so the tab row does not reshuffle between events.
        XCTAssertEqual(sections, EventSection.allCases.filter { sections.contains($0) })
    }

    func testAnEventInProgressOffersOnlyWhatItHas() throws {
        let live = try fixture("event-live", as: EventDetailResponse.self)
        let sections = live.availableSections
        XCTAssertTrue(sections.contains(.matches))
        XCTAssertTrue(sections.contains(.teams))
        // Skills run before the matches do, and these carry real scores.
        XCTAssertTrue(sections.contains(.skills))
        // Nothing has been played, so there is no bracket to draw.
        XCTAssertFalse(sections.contains(.bracket))
    }

    func testAwardsWithoutWinnersAreNotOffered() throws {
        let live = try fixture("event-live", as: EventDetailResponse.self)
        // The event lists all 18 awards it will give out, none of them won yet.
        XCTAssertFalse(live.awards.isEmpty)
        XCTAssertTrue(live.awards.allSatisfy { ($0.teamWinners ?? []).isEmpty })
        XCTAssertFalse(live.availableSections.contains(.awards),
                       "a list of categories is not a list of results")
        // The finished event has real winners and does offer them.
        let finished = try fixture("event-detail", as: EventDetailResponse.self)
        XCTAssertTrue(finished.availableSections.contains(.awards))
    }
}

/// OPR, DPR and CCWM, fitted from a real event's qualification matches.
final class PowerRatingTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func division() throws -> Division {
        try XCTUnwrap(fixture("event-detail", as: EventDetailResponse.self).divisions.first)
    }

    func testEveryTeamThatPlayedGetsARating() throws {
        let division = try division()
        let ratings = division.powerRatings()
        let played = Set(division.qualification.filter(\.isPlayed).flatMap {
            ($0.red?.numbers ?? []) + ($0.blue?.numbers ?? [])
        }.map { $0.uppercased() })
        XCTAssertFalse(played.isEmpty)
        XCTAssertEqual(Set(ratings.keys), played)
        for (team, stats) in ratings {
            XCTAssertTrue(stats.opr.isFinite, "\(team) opr")
            XCTAssertTrue(stats.dpr.isFinite, "\(team) dpr")
            XCTAssertEqual(stats.ccwm, stats.opr - stats.dpr, accuracy: 0.0001)
        }
    }

    /// The guarantee a least-squares fit actually makes.
    ///
    /// Solving the normal equations means `A.x = b` holds exactly, so this
    /// rebuilds both from the matches and checks it. This is the test that
    /// would catch a wrong solver; the size of the per-match residual, below,
    /// is a property of the sport rather than of the code.
    func testSolvesTheNormalEquationsExactly() throws {
        let division = try division()
        let ratings = division.powerRatings()

        var sides: [(teams: [String], scored: Double)] = []
        for match in division.qualification.filter(\.isPlayed) {
            guard let red = match.red, let blue = match.blue,
                  let redScore = red.score, let blueScore = blue.score else { continue }
            sides.append((red.numbers.map { $0.uppercased() }, Double(redScore)))
            sides.append((blue.numbers.map { $0.uppercased() }, Double(blueScore)))
        }
        let teams = Array(ratings.keys).sorted()
        var a = [[Double]](repeating: [Double](repeating: 0, count: teams.count), count: teams.count)
        var b = [Double](repeating: 0, count: teams.count)
        let index = Dictionary(uniqueKeysWithValues: teams.enumerated().map { ($1, $0) })
        for side in sides {
            let rows = side.teams.compactMap { index[$0] }
            for i in rows {
                b[i] += side.scored
                for j in rows { a[i][j] += 1 }
            }
        }

        for i in 0..<teams.count {
            let lhs = (0..<teams.count).reduce(0.0) { $0 + a[i][$1] * ratings[teams[$1]]!.opr }
            XCTAssertEqual(lhs, b[i], accuracy: 0.001, "row \(teams[i]) of A.x = b")
        }
    }

    func testTheFitTracksTheMatchesItWasBuiltFrom() throws {
        let division = try division()
        let ratings = division.powerRatings()
        var error = 0.0
        var total = 0.0
        var count = 0.0
        for match in division.qualification.filter(\.isPlayed) {
            for alliance in [match.red, match.blue] {
                guard let alliance, let score = alliance.score else { continue }
                let predicted = alliance.numbers
                    .compactMap { ratings[$0.uppercased()]?.opr }
                    .reduce(0, +)
                error += abs(Double(score) - predicted)
                total += Double(score)
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 0)
        // The residual is bounded against the scores themselves rather than by
        // a number picked out of the air. It does not get much tighter than
        // this: 41 teams are fitted from 82 matches, so each team is seen four
        // times, and a single broken robot moves its alliance by a hundred
        // points. On this event the mean miss is about a third of the mean
        // alliance score.
        let mean = error / count
        XCTAssertLessThan(mean, (total / count) * 0.5)
    }

    func testOffenceAndDefenceDifferAndRankSensibly() throws {
        let ratings = try division().powerRatings()
        let oprs = ratings.values.map(\.opr)
        let dprs = ratings.values.map(\.dpr)
        // A fitted rating set must actually distinguish teams.
        XCTAssertGreaterThan(oprs.max()! - oprs.min()!, 1)
        XCTAssertNotEqual(oprs.sorted(), dprs.sorted())

        // The division winner should not be among the weakest contributors.
        let top = try XCTUnwrap(division().rankings.min(by: { $0.rank < $1.rank }))
        let best = try XCTUnwrap(ratings[top.team.name.uppercased()])
        let median = oprs.sorted()[oprs.count / 2]
        XCTAssertGreaterThan(best.opr, median, "the top seed should be an above-average scorer")
    }

    func testEliminationMatchesAreExcluded() throws {
        let division = try division()
        XCTAssertFalse(division.elimination.isEmpty, "this event has a bracket")
        // Alliances in the bracket are chosen rather than drawn, so they say
        // nothing about a team on its own and must not feed the fit. A team
        // that only ever appeared in eliminations would show up otherwise.
        let qualTeams = Set(division.qualification.filter(\.isPlayed).flatMap {
            ($0.red?.numbers ?? []) + ($0.blue?.numbers ?? [])
        }.map { $0.uppercased() })
        XCTAssertTrue(Set(division.powerRatings().keys).isSubset(of: qualTeams))
    }

    func testAHalfPlayedEventIsNotRatedAtAll() throws {
        // Captured 39 matches into a 219-match schedule across 97 teams: about
        // one and a half appearances each. Solving that produced an OPR of -70
        // and a CCWM of -222 - numbers shaped like ratings that mean nothing.
        let partial = try fixture("event-partial", as: EventDetailResponse.self)
        let division = try XCTUnwrap(partial.divisions.first)
        let played = division.qualification.filter(\.isPlayed)
        XCTAssertGreaterThan(played.count, 0, "it has started")
        let teams = Set(played.flatMap { ($0.red?.numbers ?? []) + ($0.blue?.numbers ?? []) })
        XCTAssertLessThan(played.count, teams.count, "but each team is barely seen")
        XCTAssertTrue(division.powerRatings().isEmpty)
    }

    func testAFinishedEventClearsTheThreshold() throws {
        let division = try division()
        let played = division.qualification.filter(\.isPlayed)
        let teams = Set(played.flatMap { ($0.red?.numbers ?? []) + ($0.blue?.numbers ?? []) })
        XCTAssertGreaterThanOrEqual(played.count, teams.count)
        XCTAssertFalse(division.powerRatings().isEmpty)
    }

    func testAnEventWithNothingPlayedHasNoRatings() throws {
        let live = try fixture("event-live", as: EventDetailResponse.self)
        let division = try XCTUnwrap(live.divisions.first)
        XCTAssertFalse(division.qualification.isEmpty, "it has a schedule")
        XCTAssertTrue(division.powerRatings().isEmpty, "but nothing to fit yet")
    }

    func testSolverHandlesAKnownSystem() {
        // 2x + y = 5, x + 3y = 10  ->  x = 1, y = 3
        let solution = Division.solve([[2, 1], [1, 3]], [5, 10])
        let answer = try? XCTUnwrap(solution)
        XCTAssertEqual(answer?[0] ?? .nan, 1, accuracy: 0.0001)
        XCTAssertEqual(answer?[1] ?? .nan, 3, accuracy: 0.0001)
        // A singular system returns nothing rather than nonsense.
        XCTAssertNil(Division.solve([[1, 2], [2, 4]], [3, 6]))
    }
}

/// A team's standing at one event, which heads its match list.
final class EventStandingTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    func testCarriesRankRecordAndCountedStats() throws {
        let detail = try fixture("event-detail", as: EventDetailResponse.self)
        let division = try XCTUnwrap(detail.divisions.first)
        let row = try XCTUnwrap(division.rankings.min(by: { $0.rank < $1.rank }))

        let standing = try XCTUnwrap(detail.standing(for: row.team.name))
        XCTAssertEqual(standing.rank, row.rank)
        XCTAssertEqual(standing.division, division.name)
        XCTAssertEqual(standing.record, row.record)
        XCTAssertEqual(standing.wp, row.wp)
        XCTAssertEqual(standing.ap, row.ap)
        XCTAssertEqual(standing.sp, row.sp)
        XCTAssertEqual(standing.highScore, row.highScore)
        // A finished event has enough play behind it to carry fitted ratings.
        XCTAssertNotNil(standing.stats)
    }

    func testIsFoundCaseInsensitively() throws {
        let detail = try fixture("event-detail", as: EventDetailResponse.self)
        let number = try XCTUnwrap(detail.divisions.first?.rankings.first?.team.name)
        XCTAssertEqual(detail.standing(for: number.lowercased())?.rank,
                       detail.standing(for: number)?.rank)
    }

    func testATeamNotAtTheEventHasNoStanding() throws {
        let detail = try fixture("event-detail", as: EventDetailResponse.self)
        XCTAssertNil(detail.standing(for: "31260X"))
    }

    func testFittedStatsAreWithheldWhileTheEventIsYoung() throws {
        // 252H, seeded 33rd at an event 39 matches into its schedule: it has a
        // rank and a record, but nothing has been played enough to rate it.
        let partial = try fixture("event-partial", as: EventDetailResponse.self)
        let standing = try XCTUnwrap(partial.standing(for: "252H"))
        XCTAssertEqual(standing.rank, 33)
        XCTAssertEqual(standing.record, "1\u{2013}0\u{2013}0")
        XCTAssertNotNil(standing.wp)
        XCTAssertNil(standing.stats, "too little play to fit a rating")
    }

    func testTheRightDivisionIsReported() throws {
        let multi = try fixture("event-multi", as: EventDetailResponse.self)
        for division in multi.divisions where !division.rankings.isEmpty {
            let number = try XCTUnwrap(division.rankings.first?.team.name)
            XCTAssertEqual(multi.standing(for: number)?.division, division.name)
        }
    }
}

/// Ordering the standings by each column.
final class StandingSortTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func division() throws -> Division {
        try XCTUnwrap(fixture("event-detail", as: EventDetailResponse.self).divisions.first)
    }

    func testLowerDprIsBetterAndEverythingElseIsHigher() throws {
        let division = try division()
        let ratings = division.powerRatings()
        XCTAssertFalse(ratings.isEmpty)

        let byDPR = division.standings(by: .dpr, ratings: ratings)
        let dprs = byDPR.compactMap { ratings[$0.team.name.uppercased()]?.dpr }
        XCTAssertEqual(dprs, dprs.sorted(), "DPR must run smallest first")

        for sort in [StandingSort.opr, .ccwm, .wp, .ap, .sp, .high] {
            let rows = division.standings(by: sort, ratings: ratings)
            let values: [Double] = rows.compactMap { row in
                switch sort {
                case .opr: return ratings[row.team.name.uppercased()]?.opr
                case .ccwm: return ratings[row.team.name.uppercased()]?.ccwm
                case .wp: return row.wp.map(Double.init)
                case .ap: return row.ap.map(Double.init)
                case .sp: return row.sp.map(Double.init)
                default: return row.highScore.map(Double.init)
                }
            }
            XCTAssertEqual(values, values.sorted(by: >), "\(sort.rawValue) must run largest first")
        }
    }

    func testTheBestDprIsNotTheWorstTeam() throws {
        let division = try division()
        let ratings = division.powerRatings()
        let best = try XCTUnwrap(division.standings(by: .dpr, ratings: ratings).first)
        let worst = try XCTUnwrap(division.standings(by: .dpr, ratings: ratings).last)
        // Reversing the comparison would silently put the leakiest defence on
        // top, which is the mistake this ordering exists to avoid.
        XCTAssertLessThan(ratings[best.team.name.uppercased()]!.dpr,
                          ratings[worst.team.name.uppercased()]!.dpr)
    }

    func testRankOrderIsTheSeedingOrder() throws {
        let rows = try division().standings(by: .rank)
        XCTAssertEqual(rows.map(\.rank), rows.map(\.rank).sorted())
        XCTAssertEqual(rows.first?.rank, 1)
    }

    func testEverySortKeepsEveryTeam() throws {
        let division = try division()
        let ratings = division.powerRatings()
        for sort in StandingSort.allCases {
            let rows = division.standings(by: sort, ratings: ratings)
            XCTAssertEqual(rows.count, division.rankings.count, "\(sort.rawValue) dropped a team")
            XCTAssertEqual(Set(rows.map(\.team.id)), Set(division.rankings.map(\.team.id)))
        }
    }

    func testTeamsWithoutAValueSortLast() throws {
        let division = try division()
        // No ratings supplied, so every OPR is missing: the order falls back to
        // seeding rather than reversing or dropping rows.
        let rows = division.standings(by: .opr, ratings: [:])
        XCTAssertEqual(rows.map(\.rank), rows.map(\.rank).sorted())
    }

    func testFittedSortsAreOnlyOfferedWhenTheyExist() throws {
        let rated = try division().availableSorts()
        XCTAssertTrue(rated.contains(.opr))
        XCTAssertTrue(rated.contains(.dpr))
        XCTAssertTrue(rated.contains(.ccwm))

        let young = try XCTUnwrap(fixture("event-partial", as: EventDetailResponse.self).divisions.first)
        let sorts = young.availableSorts()
        XCTAssertFalse(sorts.contains(.opr))
        XCTAssertFalse(sorts.contains(.dpr))
        XCTAssertFalse(sorts.contains(.ccwm))
        // The counted columns are still there to sort by.
        XCTAssertTrue(sorts.contains(.wp))
        XCTAssertTrue(sorts.contains(.rank))
    }
}

/// Starred teams, and that they survive a restart.
final class FavouriteTeamTests: XCTestCase {
    private func store(_ name: String = #function) -> (FavouriteTeams, UserDefaults) {
        let suite = "favourites-test-\(name)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (FavouriteTeams(defaults: defaults, key: "teams"), defaults)
    }

    func testAddsRemovesAndToggles() {
        let (favourites, _) = store()
        XCTAssertTrue(favourites.teams.isEmpty)

        favourites.add(FavouriteTeam(number: "252H", name: "Holy Cow"))
        XCTAssertTrue(favourites.contains("252H"))
        XCTAssertEqual(favourites.teams.count, 1)

        // Starring twice does not make two.
        favourites.add(FavouriteTeam(number: "252H", name: "Holy Cow"))
        XCTAssertEqual(favourites.teams.count, 1)

        favourites.toggle(FavouriteTeam(number: "252H"))
        XCTAssertFalse(favourites.contains("252H"))
        favourites.toggle(FavouriteTeam(number: "252H"))
        XCTAssertTrue(favourites.contains("252H"))
    }

    func testMatchingIgnoresCase() {
        let (favourites, _) = store()
        favourites.add(FavouriteTeam(number: "252h", name: "Holy Cow"))
        XCTAssertTrue(favourites.contains("252H"))
        favourites.remove("252H")
        XCTAssertTrue(favourites.teams.isEmpty)
    }

    func testANameIsFilledInLater() {
        let (favourites, _) = store()
        // Starred from a match list, where only the number is on screen.
        favourites.add(FavouriteTeam(number: "252H"))
        XCTAssertNil(favourites.teams.first?.name)
        // Seen later somewhere that knows the name.
        favourites.add(FavouriteTeam(number: "252H", name: "Holy Cow"))
        XCTAssertEqual(favourites.teams.count, 1)
        XCTAssertEqual(favourites.teams.first?.name, "Holy Cow")
        // And a later sighting without a name does not wipe it.
        favourites.add(FavouriteTeam(number: "252H"))
        XCTAssertEqual(favourites.teams.first?.name, "Holy Cow")
    }

    func testStaysInNumericOrder() {
        let (favourites, _) = store()
        for number in ["10188S", "2A", "252H", "2011B"] {
            favourites.add(FavouriteTeam(number: number))
        }
        XCTAssertEqual(favourites.teams.map(\.number), ["2A", "252H", "2011B", "10188S"])
    }

    func testSurvivesARestart() {
        let suite = "favourites-restart-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = FavouriteTeams(defaults: defaults, key: "teams")
        first.add(FavouriteTeam(number: "252H", name: "Holy Cow"))
        first.add(FavouriteTeam(number: "2A"))

        let second = FavouriteTeams(defaults: defaults, key: "teams")
        XCTAssertEqual(second.teams.map(\.number), ["2A", "252H"])
        XCTAssertEqual(second.teams.last?.name, "Holy Cow")
    }

    func testDuplicatesWrittenByAnOlderBuildAreCleanedUp() {
        let suite = "favourites-dupes-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let stored = [FavouriteTeam(number: "252H"), FavouriteTeam(number: "252h", name: "Holy Cow")]
        defaults.set(try! JSONEncoder().encode(stored), forKey: "teams")

        let favourites = FavouriteTeams(defaults: defaults, key: "teams")
        XCTAssertEqual(favourites.teams.count, 1)
    }
}

/// Tournament momentum: a team's running scoring margin through an event.
final class MomentumTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func matches(_ team: String = "19600Z") throws -> [TeamMatch] {
        try fixture("event-detail", as: EventDetailResponse.self).matches(for: team)
    }

    func testRunningTotalIsTheSumOfTheMarginsSoFar() throws {
        let points = TeamMomentum.points(from: try matches())
        XCTAssertFalse(points.isEmpty)
        var running = 0
        for point in points {
            running += point.margin
            XCTAssertEqual(point.cumulative, running)
        }
        XCTAssertEqual(points.last?.cumulative, points.map(\.margin).reduce(0, +))
    }

    func testMarginsAgreeWithTheScores() throws {
        let matches = try matches()
        let points = TeamMomentum.points(from: matches)
        for point in points {
            let match = try XCTUnwrap(matches.first { $0.id == point.id })
            XCTAssertEqual(point.margin, try XCTUnwrap(match.scoreFor) - XCTUnwrap(match.scoreAgainst))
            // A win must move it up and a loss down; that is the whole reading.
            switch match.outcome {
            case .won: XCTAssertGreaterThan(point.margin, 0)
            case .lost: XCTAssertLessThan(point.margin, 0)
            case .tied: XCTAssertEqual(point.margin, 0)
            case .scheduled: XCTFail("an unplayed match must not be plotted")
            }
        }
    }

    func testStepsAreNumberedFromOneInPlayOrder() throws {
        let points = TeamMomentum.points(from: try matches())
        XCTAssertEqual(points.map(\.match), Array(1...points.count))
    }

    func testUnplayedMatchesAreNotPlotted() throws {
        let live = try fixture("event-partial", as: EventDetailResponse.self)
        let matches = live.matches(for: "252H")
        XCTAssertGreaterThan(matches.filter { !$0.isPlayed }.count, 0)
        let points = TeamMomentum.points(from: matches)
        XCTAssertEqual(points.count, matches.filter(\.isPlayed).count)
        // Carrying the last value forward would draw a flat line into matches
        // that have not happened.
        XCTAssertLessThan(points.count, matches.count)
    }

    func testAnUnstartedTournamentHasNoCurve() throws {
        let live = try fixture("event-live", as: EventDetailResponse.self)
        XCTAssertTrue(TeamMomentum.points(from: live.matches(for: "663D")).isEmpty)
    }

    func testTheRangeAlwaysStraddlesZero() throws {
        let points = TeamMomentum.points(from: try matches())
        let range = TeamMomentum.range(points)
        XCTAssertLessThan(range.lowerBound, 0)
        XCTAssertGreaterThan(range.upperBound, 0)
        for point in points {
            XCTAssertTrue(range.contains(Double(point.cumulative)), "\(point.cumulative) is off the chart")
        }
        // A team that only ever won still shows the zero line beneath it.
        let winning = [
            MomentumPoint(id: 1, match: 1, name: "a", margin: 30, cumulative: 30, outcome: .won),
            MomentumPoint(id: 2, match: 2, name: "b", margin: 20, cumulative: 50, outcome: .won),
        ]
        XCTAssertLessThan(TeamMomentum.range(winning).lowerBound, 0)
    }
}
