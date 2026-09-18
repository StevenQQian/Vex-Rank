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
