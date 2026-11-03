import XCTest
@testable import VEXRankKit

final class UsageLogTests: XCTestCase {
    private func freshLog() -> UsageLog {
        let suite = "usage-tests-\(UUID().uuidString)"
        return UsageLog(defaults: UserDefaults(suiteName: suite)!, key: "usage")
    }

    func testRecordsAreBoundedAndRepeatsWithinMinutesCountOnce() {
        let log = freshLog()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        log.record(UsageRecord(kind: .team, key: "252H", label: "252H", place: nil, program: "V5RC", at: start))
        log.record(UsageRecord(kind: .team, key: "252H", label: "252H", place: nil, program: "V5RC", at: start.addingTimeInterval(60)))
        XCTAssertEqual(log.records.count, 1, "re-opening within five minutes is one visit")
        for i in 0..<(UsageLog.limit + 10) {
            log.record(UsageRecord(kind: .event, key: "\(i)", label: "E\(i)", place: nil, program: "V5RC", at: start.addingTimeInterval(Double(i) * 600)))
        }
        XCTAssertEqual(log.records.count, UsageLog.limit)
        XCTAssertEqual(log.records.last?.key, "\(UsageLog.limit + 9)")
    }

    func testTurningItOffStopsRecordingAndClears() {
        let log = freshLog()
        log.record(UsageRecord(kind: .team, key: "1A", label: "1A", place: nil, program: "V5RC"))
        log.isEnabled = false
        XCTAssertTrue(log.records.isEmpty)
        log.record(UsageRecord(kind: .team, key: "2A", label: "2A", place: nil, program: "V5RC"))
        XCTAssertTrue(log.records.isEmpty)
    }

    func testSummaryWeighsRecentVisitsMost() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86400
        var records: [UsageRecord] = []
        // Three visits to 1A two months ago, two to 252H this week.
        for i in 0..<3 { records.append(UsageRecord(kind: .team, key: "1A", label: "1A", place: "Ohio, United States", program: "V5RC", at: now.addingTimeInterval(-60 * day + Double(i) * 600))) }
        for i in 0..<2 { records.append(UsageRecord(kind: .team, key: "252H", label: "252H", place: "Ontario, Canada", program: "V5RC", at: now.addingTimeInterval(-2 * day + Double(i) * 600))) }
        records.append(UsageRecord(kind: .event, key: "64234", label: "Caution Tape", place: "Markham, Ontario, Canada", program: "V5RC", at: now.addingTimeInterval(-day)))
        let summary = UsageSummary(records: records, now: now)
        XCTAssertEqual(summary.teams.first?.key, "252H")
        XCTAssertEqual(summary.teams.first?.visits, 2)
        XCTAssertEqual(summary.places.first?.name, "Canada")
        XCTAssertEqual(summary.program, "V5RC")
        XCTAssertEqual(summary.visits, 6)
    }

    private func event(_ id: String, _ date: String, city: String, region: String) throws -> VEXEvent {
        let json: [String: Any] = ["id": id, "date": date, "name": "Event \(id)", "city": city, "region": region]
        return try JSONDecoder().decode(VEXEvent.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testCandidatesAreRealTeamsAndEventsBestFirst() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15
        let records = [
            UsageRecord(kind: .team, key: "252H", label: "252H", place: nil, program: "V5RC", at: now),
            UsageRecord(kind: .event, key: "e1", label: "Event e1", place: "Markham, Ontario, Canada", program: "V5RC", at: now),
        ]
        let events = [
            try event("e1", "2027-02-01", city: "Markham, Ontario", region: "Canada"),
            try event("e2", "2027-03-01", city: "Toronto, Ontario", region: "Canada"),
            try event("e3", "2027-03-01", city: "Austin, Texas", region: "United States"),
            try event("old", "2026-01-01", city: "Ottawa, Ontario", region: "Canada"),
        ]
        let candidates = InterestSuggestions.candidates(summary: UsageSummary(records: records, now: now), favourites: ["1a"], events: events, now: now)
        let ids = candidates.map(\.id)
        XCTAssertEqual(ids.first, "event:e1", "an event you looked at that is coming up comes first")
        XCTAssertTrue(ids.contains("team:252H"))
        XCTAssertTrue(ids.contains("team:1A"), "favourites are offered")
        XCTAssertTrue(ids.contains("event:e2"), "an upcoming event where you follow events")
        XCTAssertFalse(ids.contains("event:e3"), "not somewhere you follow")
        XCTAssertFalse(ids.contains("event:old"), "not one that is over")
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicates")
    }
}
