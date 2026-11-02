import XCTest
@testable import VEXRankKit

/// Mirrors website/tests/stream-jumper.test.mjs.
final class StreamJumperTests: XCTestCase {
    func testYouTubeIDsFromEveryLinkShapeNoneFromChannels() {
        for link in ["https://www.youtube.com/watch?v=3XiT_3haGR4", "https://youtu.be/3XiT_3haGR4?t=5", "https://youtube.com/live/3XiT_3haGR4?feature=share", "https://www.youtube.com/embed/3XiT_3haGR4", "https://m.youtube.com/watch?v=3XiT_3haGR4&t=1"] {
            XCTAssertEqual(StreamJumper.youtubeID(link), "3XiT_3haGR4", link)
        }
        for link in ["https://www.youtube.com/@CautionTape/streams", "https://www.youtube.com/channel/UC-grQ9qvMoKXjtxOPDrC-yg", "https://twitch.tv/x", "not a link"] {
            XCTAssertNil(StreamJumper.youtubeID(link), link)
        }
    }

    func testStreamsFromWebcastNotesThenViewersOncePerVideo() {
        let notes = "Livestream (Saturday, from 10:00 AM ET): https://www.youtube.com/watch?v=3XiT_3haGR4. Channel: https://www.youtube.com/@cautiontape"
        let result = StreamJumper.streams(webcast: notes, added: [EventStream(videoId: "3XiT_3haGR4"), EventStream(videoId: "abcdefghijk")])
        XCTAssertEqual(result.streams.map { [$0.videoId, $0.source ?? ""] }, [["3XiT_3haGR4", "event"], ["abcdefghijk", "viewer"]])
        XCTAssertEqual(result.others, ["https://www.youtube.com/@cautiontape"])
    }

    // Caution Tape: scheduled 9:00, 9:04, 9:08 - started 9:33:13, 9:38:33, 9:45:29.
    private func matches() throws -> [Int: DivisionMatch] {
        let rows: [[String: Any]] = [
            ["id": 1, "name": "Qualifier #1", "round": 2, "scheduled": "2026-10-31T09:00:00-04:00", "started": "2026-10-31T09:33:13-04:00"],
            ["id": 2, "name": "Qualifier #2", "round": 2, "scheduled": "2026-10-31T09:04:00-04:00", "started": "2026-10-31T09:38:33-04:00"],
            ["id": 3, "name": "Qualifier #3", "round": 2, "scheduled": "2026-10-31T09:08:00-04:00", "started": "2026-10-31T09:45:29-04:00"],
            ["id": 4, "name": "Qualifier #4", "round": 2, "scheduled": "2026-10-31T09:12:00-04:00"],
        ]
        let decoded = try JSONDecoder().decode([DivisionMatch].self, from: JSONSerialization.data(withJSONObject: rows))
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    func testSyncPlacesMatchesByWhenTheyStartedNotTheSchedule() throws {
        let m = try matches()
        let streams = [EventStream(videoId: "v1", sync: .init(matchId: 2, seconds: 1800))]
        func jump(_ id: Int, nudges: [String: Double] = [:]) -> MatchJump? { StreamJumper.jump(to: m[id]!, divisionId: nil, streams: streams, matches: m, nudges: nudges) }
        XCTAssertEqual(jump(2), MatchJump(videoId: "v1", seconds: 1800))
        XCTAssertEqual(jump(3), MatchJump(videoId: "v1", seconds: 2216), "6m56s later, not the scheduled 4m")
        XCTAssertEqual(jump(1), MatchJump(videoId: "v1", seconds: 1480))
        XCTAssertNil(jump(4), "not played yet")
        XCTAssertEqual(jump(3, nudges: ["v1": -10]), MatchJump(videoId: "v1", seconds: 2206))
    }

    func testYouTubeStartTimeAndAStreamPerDay() throws {
        let m = try matches()
        let one = [EventStream(videoId: "v1", startTime: "2026-10-31T09:35:00-04:00")]
        XCTAssertNil(StreamJumper.jump(to: m[1]!, divisionId: nil, streams: one, matches: m))
        XCTAssertEqual(StreamJumper.jump(to: m[2]!, divisionId: nil, streams: one, matches: m), MatchJump(videoId: "v1", seconds: 213))
        let days = [EventStream(videoId: "day1", startTime: "2026-10-31T08:00:00-04:00"), EventStream(videoId: "day2", startTime: "2026-10-31T09:40:00-04:00")]
        XCTAssertEqual(StreamJumper.jump(to: m[2]!, divisionId: nil, streams: days, matches: m)?.videoId, "day1")
        XCTAssertEqual(StreamJumper.jump(to: m[3]!, divisionId: nil, streams: days, matches: m)?.videoId, "day2")
        XCTAssertNil(StreamJumper.jump(to: m[2]!, divisionId: nil, streams: [EventStream(videoId: "x")], matches: m), "an untimed stream")
        XCTAssertEqual(StreamJumper.videoTime(3725), "1:02:05")
        XCTAssertEqual(StreamJumper.videoTime(65), "1:05")
    }
}
