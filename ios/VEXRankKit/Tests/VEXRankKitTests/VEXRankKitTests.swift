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
