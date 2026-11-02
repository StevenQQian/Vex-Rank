import Foundation

/// The jumper, after OpenScout's: an event's livestream beside its schedule,
/// and a jump from any played match to the moment it started. Mirrors
/// website/lib/stream-jumper.mjs - see there for the reasoning.
///
/// Matches are placed by when they actually `started`, never by their
/// scheduled time (events run late), from one known point per stream: a sync
/// ("this match starts here", which anyone can set for everyone) or YouTube's
/// own start time. A per-viewer nudge takes up the remaining seconds.
public struct EventStream: Codable, Sendable, Hashable, Identifiable {
    public struct Sync: Codable, Sendable, Hashable {
        public let matchId: Int
        public let seconds: Double
        public init(matchId: Int, seconds: Double) { self.matchId = matchId; self.seconds = seconds }
    }

    public let videoId: String
    public var url: String?
    public var divisionId: Int?
    public var sync: Sync?
    public var startTime: String?
    /// "event" (the organizer's webcast notes) or "viewer" (added here).
    public var source: String?

    public var id: String { videoId }

    public init(videoId: String, url: String? = nil, divisionId: Int? = nil, sync: Sync? = nil, startTime: String? = nil, source: String? = nil) {
        self.videoId = videoId; self.url = url; self.divisionId = divisionId; self.sync = sync; self.startTime = startTime; self.source = source
    }

    public var isTimed: Bool { sync != nil || startTime != nil }
}

public struct SharedStreamsResponse: Codable, Sendable {
    public let streams: [EventStream]
}

public struct MatchJump: Sendable, Hashable {
    public let videoId: String
    public let seconds: Int
}

public enum StreamJumper {
    /// The YouTube video id in a link, or nil. Channel and playlist links have none.
    public static func youtubeID(_ link: String) -> String? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.replacingOccurrences(of: #"^(www|m|music)\."#, with: "", options: .regularExpression)
        let parts = url.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" { id = parts.first }
        else if host == "youtube.com" || host == "youtube-nocookie.com" {
            if parts.first == "watch" { id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value }
            else if let kind = parts.first, ["live", "embed", "shorts", "v"].contains(kind), parts.count > 1 { id = parts[1] }
        }
        guard let id, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    /// Every link in a block of text, in order, once each.
    public static func links(in text: String?) -> [String] {
        guard let text, let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"')\]]+"#) else { return [] }
        var seen = Set<String>(), found: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let link = String(text[range]).replacingOccurrences(of: #"[.,;:!?]+$"#, with: "", options: .regularExpression)
            if seen.insert(link).inserted { found.append(link) }
        }
        return found
    }

    /// The event's streams: YouTube videos in its webcast notes, then shared or
    /// added ones, once per video; other links (a channel page) come back to
    /// open as plain links.
    public static func streams(webcast: String?, added: [EventStream] = []) -> (streams: [EventStream], others: [String]) {
        var streams: [EventStream] = [], others: [String] = [], seen = Set<String>()
        for link in links(in: webcast) {
            if let id = youtubeID(link) {
                if seen.insert(id).inserted { streams.append(EventStream(videoId: id, url: link, source: "event")) }
            } else { others.append(link) }
        }
        for stream in added where seen.insert(stream.videoId).inserted {
            var copy = stream
            if copy.source == nil { copy.source = "viewer" }
            streams.append(copy)
        }
        return (streams, others)
    }

    static func time(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    /// When a stream's video starts, from its sync point or YouTube's start time.
    public static func origin(of stream: EventStream, matches: [Int: DivisionMatch]) -> Date? {
        if let sync = stream.sync, let anchor = time(matches[sync.matchId]?.started) {
            return anchor.addingTimeInterval(-sync.seconds)
        }
        return time(stream.startTime)
    }

    /// Where in the video `match` begins, with the viewer's nudge - or nil when
    /// it has not been played, no stream is timed, or it falls before the video.
    /// Of the timed streams for its division, the one that began most recently
    /// before the match is the one it is on (a stream per day, a restart).
    public static func jump(to match: DivisionMatch, divisionId: Int?, streams: [EventStream],
                            matches: [Int: DivisionMatch], divisionOf: [Int: Int] = [:], nudges: [String: Double] = [:]) -> MatchJump? {
        guard let started = time(match.started) else { return nil }
        let timed = streams.compactMap { stream -> (EventStream, Date)? in
            guard let origin = origin(of: stream, matches: matches) else { return nil }
            if let division = stream.divisionId, let mine = divisionId, division != mine { return nil }
            return (stream, origin)
        }
        guard !timed.isEmpty else { return nil }
        let before = timed.filter { $0.1 <= started }
        let pick = before.max { $0.1 < $1.1 } ?? timed.min { $0.1 < $1.1 }!
        let seconds = (started.timeIntervalSince(pick.1) + (nudges[pick.0.videoId] ?? 0)).rounded()
        return seconds >= 0 ? MatchJump(videoId: pick.0.videoId, seconds: Int(seconds)) : nil
    }

    /// "1:02:03" / "4:05" for a video position.
    public static func videoTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded())), h = s / 3600, m = s % 3600 / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }
}

extension EventDetailResponse {
    /// Every match at the event by id, for placing matches on a stream.
    public var matchesByID: [Int: DivisionMatch] {
        Dictionary(divisions.flatMap { $0.matches ?? [] }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Each match's division id.
    public var divisionByMatch: [Int: Int] {
        Dictionary(divisions.flatMap { division in (division.matches ?? []).map { ($0.id, division.id) } }, uniquingKeysWith: { first, _ in first })
    }
}
