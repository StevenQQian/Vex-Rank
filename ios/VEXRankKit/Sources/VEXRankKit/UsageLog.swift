import Foundation

/// What the reader opens in the app - teams, events, a team at an event - kept
/// on the device only, for the For You overview. Nothing here is sent anywhere:
/// the overview is worked out on the phone, by Apple Intelligence where the
/// device has it.
public struct UsageRecord: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case team, event, teamAtEvent }

    public let kind: Kind
    /// Team number, or event id; "eventID|team" for a team at an event.
    public let key: String
    /// What to show: the team number or the event name.
    public let label: String
    /// Where: an event's place, or a team's location.
    public let place: String?
    /// "V5RC" or "VIQRC".
    public let program: String
    public let at: Date

    public init(kind: Kind, key: String, label: String, place: String?, program: String, at: Date = Date()) {
        self.kind = kind; self.key = key; self.label = label; self.place = place; self.program = program; self.at = at
    }
}

/// The on-device usage record. Bounded, and the reader can turn it off or
/// clear it from the For You tab.
public final class UsageLog: @unchecked Sendable {
    public static let shared = UsageLog()

    static let limit = 400
    private let defaults: UserDefaults
    private let key: String
    private let enabledKey: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "vexrank-usage") {
        self.defaults = defaults
        self.key = key
        self.enabledKey = key + "-enabled"
    }

    /// Whether the app remembers what the reader opens. On unless turned off.
    public var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey); if !newValue { clear() } }
    }

    public var records: [UsageRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([UsageRecord].self, from: data)) ?? []
    }

    public func record(_ record: UsageRecord) {
        guard isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        var all = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([UsageRecord].self, from: $0) }) ?? []
        // Re-opening the same screen within a few minutes is one visit, not several.
        if let last = all.last, last.kind == record.kind, last.key == record.key, record.at.timeIntervalSince(last.at) < 300 { return }
        all.append(record)
        if all.count > Self.limit { all.removeFirst(all.count - Self.limit) }
        defaults.set(try? JSONEncoder().encode(all), forKey: key)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}

/// What the reader's usage says they follow, recent visits counting most
/// (a visit's weight halves every two weeks).
public struct UsageSummary: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public let key: String
        public let label: String
        public let place: String?
        public let program: String
        public let visits: Int
        public let weight: Double
        public let lastSeen: Date
    }

    public let teams: [Item]
    public let events: [Item]
    /// Places the reader's events (and teams) are in, most followed first.
    public let places: [(name: String, weight: Double)]
    /// The program the reader mostly uses.
    public let program: String?
    public let visits: Int

    public static func == (a: UsageSummary, b: UsageSummary) -> Bool {
        a.teams == b.teams && a.events == b.events && a.program == b.program && a.visits == b.visits && a.places.map(\.name) == b.places.map(\.name)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(teams); hasher.combine(events); hasher.combine(visits) }

    public var isEmpty: Bool { visits == 0 }

    static let halfLife: TimeInterval = 14 * 86400

    public init(records: [UsageRecord], now: Date = Date()) {
        func weight(_ at: Date) -> Double { pow(0.5, max(0, now.timeIntervalSince(at)) / Self.halfLife) }
        var teams: [String: (UsageRecord, Int, Double, Date)] = [:]
        var events: [String: (UsageRecord, Int, Double, Date)] = [:]
        var places: [String: Double] = [:]
        var programs: [String: Double] = [:]
        for record in records {
            let w = weight(record.at)
            programs[record.program, default: 0] += w
            switch record.kind {
            case .team:
                let entry = teams[record.key.uppercased()] ?? (record, 0, 0, record.at)
                teams[record.key.uppercased()] = (record, entry.1 + 1, entry.2 + w, max(entry.3, record.at))
            case .event:
                let entry = events[record.key] ?? (record, 0, 0, record.at)
                events[record.key] = (record, entry.1 + 1, entry.2 + w, max(entry.3, record.at))
            case .teamAtEvent:
                // Following a team through an event says something about both.
                let parts = record.key.split(separator: "|").map(String.init)
                if parts.count == 2 {
                    let team = parts[1].uppercased()
                    let entry = teams[team] ?? (UsageRecord(kind: .team, key: team, label: team, place: nil, program: record.program, at: record.at), 0, 0, record.at)
                    teams[team] = (entry.0, entry.1 + 1, entry.2 + w * 0.5, max(entry.3, record.at))
                }
            }
            if let place = record.place?.split(separator: ",").last?.trimmingCharacters(in: .whitespaces), !place.isEmpty {
                places[place, default: 0] += w
            }
        }
        func items(_ map: [String: (UsageRecord, Int, Double, Date)]) -> [Item] {
            map.map { key, value in Item(key: key, label: value.0.label, place: value.0.place, program: value.0.program, visits: value.1, weight: value.2, lastSeen: value.3) }
                .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.lastSeen > $1.lastSeen }
        }
        self.teams = items(teams)
        self.events = items(events)
        self.places = places.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        self.program = programs.max { $0.value < $1.value }?.key
        self.visits = records.count
    }
}

/// A suggestion the overview can make: always a real team or event, so
/// whatever orders and explains them (Apple Intelligence, or the fallback
/// ranking) can never point the reader at something that does not exist.
public struct InterestCandidate: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable {
        case team(String)
        case event(VEXEvent)
    }

    /// "team:31260X", "event:64234" - what Apple Intelligence picks by.
    public let id: String
    public let target: Target
    public let title: String
    public let subtitle: String
    /// Why, in plain words - used as written when Apple Intelligence is not there.
    public let reason: String
    public let score: Double
    /// The plain facts Apple Intelligence is given about it, in the reader's
    /// terms ("You opened its page 5 times."), so it has nothing to guess.
    public var fact: String = ""
}

public enum InterestSuggestions {
    /// Candidates from the reader's usage, their favourites and the season's
    /// events, best first by a simple score (the fallback order).
    public static func candidates(summary: UsageSummary, favourites: [String], events: [VEXEvent], now: Date = Date()) -> [InterestCandidate] {
        var found: [String: InterestCandidate] = [:]
        func add(_ candidate: InterestCandidate) {
            if let existing = found[candidate.id], existing.score >= candidate.score { return }
            found[candidate.id] = candidate
        }
        let today = Calendar.current.startOfDay(for: now)
        let soon = events.filter { ($0.day.map { $0 >= today } ?? false) && !($0.status ?? "").lowercased().contains("cancel") }

        // Teams the reader keeps opening.
        for (index, team) in summary.teams.prefix(6).enumerated() {
            add(InterestCandidate(id: "team:\(team.key)", target: .team(team.key), title: team.label,
                                  subtitle: team.visits == 1 ? "You opened it once recently" : "You opened it \(team.visits) times",
                                  reason: "You keep checking on \(team.label).", score: 3 + team.weight - Double(index) * 0.1,
                                  fact: "team \(team.label). You opened its page \(team.visits == 1 ? "once" : "\(team.visits) times")."))
        }
        // Favourite teams.
        for number in favourites.prefix(8) {
            add(InterestCandidate(id: "team:\(number.uppercased())", target: .team(number.uppercased()), title: number.uppercased(),
                                  subtitle: "One of your favourites", reason: "\(number.uppercased()) is one of your favourite teams.", score: 2.5,
                                  fact: "team \(number.uppercased()). It is one of your favourite teams."))
        }
        // Events the reader looked at that have not happened yet.
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for event in summary.events.prefix(8) {
            guard let full = byID[event.key], soon.contains(full) else { continue }
            add(InterestCandidate(id: "event:\(full.id)", target: .event(full), title: full.name,
                                  subtitle: [full.date, full.place].filter { !$0.isEmpty }.joined(separator: " · "),
                                  reason: "You looked at this event and it is coming up.", score: 3.5 + event.weight,
                                  fact: "\(full.name), on \(full.date) in \(full.place). You opened it, and it has not happened yet."))
        }
        // Upcoming events in the places the reader follows.
        let places = summary.places.prefix(3).map { $0.name.lowercased() }
        if !places.isEmpty {
            let near = soon.filter { event in places.contains { place in event.place.lowercased().contains(place) } }
                .sorted { ($0.day ?? .distantFuture) < ($1.day ?? .distantFuture) }
            for (index, event) in near.prefix(6).enumerated() where found["event:\(event.id)"] == nil {
                let place = places.first { event.place.lowercased().contains($0) } ?? ""
                add(InterestCandidate(id: "event:\(event.id)", target: .event(event), title: event.name,
                                      subtitle: [event.date, event.place].filter { !$0.isEmpty }.joined(separator: " · "),
                                      reason: "Coming up in \(place.capitalized), where the teams and events you follow are.", score: 2 - Double(index) * 0.15,
                                      fact: "\(event.name), on \(event.date) in \(event.place). You have not opened it yet. It is near where most of what you follow is."))
            }
        }
        return found.values.sorted { $0.score > $1.score }
    }
}
