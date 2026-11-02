import XCTest
@testable import VEXRankKit

/// Mirrors website/tests/disqualifications.test.mjs.
final class RulingsTests: XCTestCase {
    private func side(_ color: String, _ score: Int, _ teams: String...) -> [String: Any] {
        ["color": color, "score": score, "teams": teams.enumerated().map { ["team": ["id": $0.offset + score * 10 + color.count, "name": $0.element]] }]
    }
    private func division(_ matches: [(Int, [String: Any], [String: Any])], rankings: [(String, Int, Int, Int)]) throws -> Division {
        let json: [String: Any] = [
            "id": 1, "name": "Division 1",
            "matches": matches.map { ["id": $0.0, "name": "Qualifier #\($0.0)", "round": 2, "alliances": [$0.1, $0.2]] },
            "rankings": rankings.enumerated().map { ["rank": $0.offset + 1, "team": ["id": $0.offset + 1000, "name": $0.element.0], "wins": $0.element.1, "losses": $0.element.2, "ties": $0.element.3] },
        ]
        return try JSONDecoder().decode(Division.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testIQZeroStationBesideAScoringPartnerIsADQ() throws {
        let d = try division([(1, side("red", 144, "19970A"), side("blue", 0, "5216A")), (2, side("red", 0, "1A"), side("blue", 0, "2A"))], rankings: [])
        let rulings = d.officialRulings(iq: true)
        XCTAssertEqual(rulings.ruling(match: 1, team: "5216A"), .dq)
        XCTAssertNil(rulings.ruling(match: 1, team: "19970A"))
        XCTAssertNil(rulings.byMatch[2], "an unplayed 0-0 is not a DQ")
        let partial = try division([(3, side("red", 90, "7A"), side("blue", 85, "8A"))], rankings: []).officialRulings(iq: true)
        XCTAssertEqual(partial.ruling(match: 3, team: "8A"), .dq, "any mismatch marks the lower station, as OpenScout does")
    }

    func testEveryWinOverturnedIsARuledLoss() throws {
        let d = try division([(5, side("red", 27, "45519S", "45519B"), side("blue", 30, "3388G", "2088Y")),
                              (7, side("red", 0, "45519J", "3388G"), side("blue", 22, "14353S", "45519Z"))],
                             rankings: [("3388G", 0, 2, 0)])
        XCTAssertEqual(d.officialRulings(iq: false).ruling(match: 5, team: "3388G"), .ruledLoss)
    }

    func testEveryNonWinBecomingAWinIsARuledWin() throws {
        let d = try division([(89, side("red", 83, "2145V", "32K"), side("blue", 93, "2567U", "2567M"))], rankings: [("32K", 1, 0, 0)])
        XCTAssertEqual(d.officialRulings(iq: false).ruling(match: 89, team: "32K"), .ruledWin)
    }

    func testAnAmbiguousGapMarksNothing() throws {
        let d = try division([(1, side("red", 50, "A1", "B1"), side("blue", 10, "C1", "D1")),
                              (2, side("red", 60, "A1", "E1"), side("blue", 20, "F1", "G1"))],
                             rankings: [("A1", 1, 1, 0)])
        let rulings = d.officialRulings(iq: false)
        XCTAssertTrue(rulings.byMatch.isEmpty)
        XCTAssertEqual(rulings.unresolved, ["A1"])
    }
}
