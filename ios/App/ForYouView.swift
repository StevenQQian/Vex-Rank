import SwiftUI
import OSLog
import VEXRankKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// For You: an overview of what the reader seems to follow, from what they
/// open in the app (VEXRankKit/UsageLog.swift), with suggestions to open next.
///
/// Where the device has Apple Intelligence (iOS 26, a supported iPhone, turned
/// on), its on-device model writes the overview and picks and explains the
/// suggestions - choosing only among real teams and events the app offers it,
/// so it cannot invent one. Everywhere else the same suggestions come in a
/// simple ranked order. Either way nothing leaves the phone.
@available(iOS 17.0, *)
struct ForYouView: View {
    @Environment(\.vexTheme) private var theme
    @Environment(\.program) private var program
    @Environment(\.favouriteTeams) private var favourites
    @State private var model = ForYouModel()
    @State private var remembering = UsageLog.shared.isEnabled
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                overviewCard
            }
            .listRowBackground(theme.surface)

            if !model.suggestions.isEmpty {
                Section("Suggested for you") {
                    ForEach(model.suggestions) { suggestion in
                        switch suggestion.destination {
                        case .team(let ref): NavigationLink(value: ref) { row(suggestion) }
                        case .event(let ref): NavigationLink(value: ref) { row(suggestion) }
                        }
                    }
                }
                .listRowBackground(theme.surface)
            }

            if let summary = model.summary, !summary.isEmpty {
                Section("Your activity") {
                    if !summary.teams.isEmpty {
                        LabeledContent("Teams you open most", value: summary.teams.prefix(3).map(\.label).joined(separator: ", "))
                    }
                    if let place = summary.places.first?.name {
                        LabeledContent("Where your events are", value: place)
                    }
                    LabeledContent("Screens opened", value: String(summary.visits))
                }
                .font(.footnote)
                .listRowBackground(theme.surface)
            }

            Section {
                Toggle("Remember what I open", isOn: $remembering)
                    .onChange(of: remembering) { _, on in
                        UsageLog.shared.isEnabled = on
                        Task { await model.load(program: program, favourites: favourites.teams.map(\.number), force: true) }
                    }
                Button("Clear my activity", role: .destructive) { confirmClear = true }
                    .disabled(model.summary?.isEmpty ?? true)
            } footer: {
                Text("What you open is kept only on this iPhone and never sent anywhere. \(model.usesAppleIntelligence ? "Apple Intelligence works on it on the device." : "")")
            }
            .tint(theme.accent)
            .listRowBackground(theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.page)
        .refreshable { await model.load(program: program, favourites: favourites.teams.map(\.number), force: true) }
        .task(id: program) { await model.load(program: program, favourites: favourites.teams.map(\.number)) }
        .confirmationDialog("Clear what Scouting Cat remembers you opening?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear activity", role: .destructive) {
                UsageLog.shared.clear()
                Task { await model.load(program: program, favourites: favourites.teams.map(\.number), force: true) }
            }
        }
    }

    private func row(_ suggestion: ForYouSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.isTeam ? "person.2" : "calendar")
                    .foregroundStyle(theme.accent).font(.caption)
                Text(suggestion.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
            if !suggestion.subtitle.isEmpty {
                Text(suggestion.subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.usesAppleIntelligence ? "apple.intelligence" : "sparkles")
                    .foregroundStyle(theme.accent)
                Text(model.usesAppleIntelligence ? "APPLE INTELLIGENCE" : "YOUR OVERVIEW")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
            }
            Text(model.headline).font(.headline)
            if let note = model.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One suggestion, ready to show and open.
struct ForYouSuggestion: Identifiable, Hashable {
    enum Destination: Hashable { case team(TeamRef), event(EventRef) }
    let id: String
    let title: String
    let subtitle: String
    let reason: String
    let destination: Destination
    var isTeam: Bool { if case .team = destination { return true } else { return false } }
}

@available(iOS 17.0, *)
@Observable
@MainActor
final class ForYouModel {
    private(set) var summary: UsageSummary?
    private(set) var suggestions: [ForYouSuggestion] = []
    private(set) var headline = "Open a few teams and events, and this fills with what you follow."
    private(set) var note: String?
    private(set) var usesAppleIntelligence = false
    private(set) var loading = false
    private var loadedFor: String?

    func load(program: Program, favourites: [String], force: Bool = false) async {
        let records = UsageLog.shared.records.filter { $0.program == program.rawValue }
        let signature = "\(program.rawValue)|\(records.count)|\(records.last?.at.timeIntervalSince1970 ?? 0)|\(favourites.joined(separator: ","))"
        if !force, signature == loadedFor { return }
        loadedFor = signature
        loading = true
        defer { loading = false }

        let summary = UsageSummary(records: records)
        self.summary = summary
        // Teams first, from what is already on the phone; events once the
        // season's list has arrived.
        let early = InterestSuggestions.candidates(summary: summary, favourites: favourites, events: [])
        if !early.isEmpty {
            suggestions = early.prefix(6).map { Self.suggestion($0, reason: $0.reason) }
            headline = Self.plainHeadline(summary)
        }
        let events = (try? await VEXRankAPI.shared.events())?.events ?? []
        let candidates = InterestSuggestions.candidates(summary: summary, favourites: favourites, events: events)
        guard !summary.isEmpty || !candidates.isEmpty else {
            headline = "Open a few teams and events, and this fills with what you follow."
            note = UsageLog.shared.isEnabled ? nil : "Remembering what you open is turned off."
            suggestions = []
            usesAppleIntelligence = false
            return
        }

        // The ranked suggestions straight away; Apple Intelligence's, where the
        // device has it, replace them when it has written them.
        usesAppleIntelligence = false
        suggestions = candidates.prefix(6).map { Self.suggestion($0, reason: $0.reason) }
        headline = Self.plainHeadline(summary)
        note = Self.unavailableNote()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            note = "Apple Intelligence is writing your overview…"
            if let written = await Self.withTimeout(seconds: 20, { await AppleIntelligenceOverview.write(summary: summary, candidates: candidates, program: program) }) {
                headline = written.headline
                suggestions = written.picks
                note = nil
                usesAppleIntelligence = true
            } else {
                note = "Apple Intelligence could not write an overview just now; these are ranked from your activity. Pull to try again."
            }
        }
        #endif
    }

    /// `work`, or nil if it has not finished in time - a slow model never
    /// leaves the tab waiting.
    nonisolated static func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    nonisolated static func suggestion(_ candidate: InterestCandidate, reason: String) -> ForYouSuggestion {
        let destination: ForYouSuggestion.Destination
        switch candidate.target {
        case .team(let number): destination = .team(TeamRef(number))
        case .event(let event): destination = .event(EventRef(id: event.id, name: event.name, day: event.day, place: event.place, isUpcoming: event.isUpcoming))
        }
        return ForYouSuggestion(id: candidate.id, title: candidate.title, subtitle: candidate.subtitle, reason: reason, destination: destination)
    }

    nonisolated static func plainHeadline(_ summary: UsageSummary) -> String {
        if let team = summary.teams.first, let place = summary.places.first?.name {
            return "You check on \(team.label) most, and most of what you follow is in \(place)."
        }
        if let team = summary.teams.first { return "You follow \(team.label) most." }
        if let place = summary.places.first?.name { return "Most of what you follow is in \(place)." }
        return "Here is what is coming up for the teams you follow."
    }

    /// Why Apple Intelligence is not writing this, in the reader's terms.
    static func unavailableNote() -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings for a written overview."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready on this iPhone; a written overview will follow."
            case .unavailable(.deviceNotEligible): return "Suggestions are ranked from your activity; this iPhone does not support Apple Intelligence."
            case .unavailable: return nil
            }
        }
        #endif
        return "Suggestions are ranked from your activity. A written overview needs Apple Intelligence (iOS 26)."
    }
}

#if canImport(FoundationModels)
/// The on-device model's part: a one-line overview, and which candidates to
/// suggest in what order, each with a reason. It picks by id from the list it
/// is given; any id that is not on the list is dropped.
@available(iOS 26.0, *)
enum AppleIntelligenceOverview {
    @Generable
    struct Overview {
        @Guide(description: "One sentence to the reader, starting with You, under 120 characters, saying what they seem to follow.")
        var headline: String
        @Guide(description: "The best suggestions, most relevant first, chosen only from the candidate ids given.", .maximumCount(6))
        var picks: [Pick]
    }

    @Generable
    struct Pick {
        @Guide(description: "A candidate id exactly as given, such as team:252H or event:64234.")
        var id: String
        @Guide(description: "One short sentence to the reader (use you), under 90 characters, why to open it next, based only on the facts given.")
        var reason: String
    }

    static func write(summary: UsageSummary, candidates: [InterestCandidate], program: Program) async -> (headline: String, picks: [ForYouSuggestion])? {
        guard case .available = SystemLanguageModel.default.availability, !candidates.isEmpty else { return nil }
        let offered = Array(candidates.prefix(14))
        let byID = Dictionary(offered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let session = LanguageModelSession(instructions: """
            You write the For You page of a \(program == .viqrc ? "VEX IQ" : "VEX V5") robotics competition scouting app, speaking directly to the reader as "you".
            Use only the facts given. Never invent teams, events, results, dates or places.
            Keep sentences short, plain and friendly. Team numbers like 252H are team names: write them exactly as given.
            """)
        var facts: [String] = []
        if !summary.teams.isEmpty {
            facts.append("- You opened the pages of " + summary.teams.prefix(5).map { "team \($0.label) (\($0.visits == 1 ? "once" : "\($0.visits) times"))" }.joined(separator: ", ") + ".")
        }
        if !summary.events.isEmpty { facts.append("- You opened the events " + summary.events.prefix(4).map(\.label).joined(separator: "; ") + ".") }
        if let place = summary.places.first?.name { facts.append("- Most of the teams and events you open are in \(place).") }
        let list = offered.map { "- \($0.id): \($0.fact.isEmpty ? "\($0.title). \($0.reason)" : $0.fact)" }.joined(separator: "\n")
        let prompt = """
            What the reader has done in the app:
            \(facts.joined(separator: "\n"))

            Candidates (pick only from these ids):
            \(list)

            First, sum up in one sentence what the reader seems to be interested in overall (teams, events, places). Do not repeat a reason as the summary.
            Then pick up to six candidates worth opening next, best first. For each, give a reason in your own words, addressed to the reader, using only that candidate's facts.
            """
        do {
            let response = try await session.respond(to: prompt, generating: Overview.self)
            var seen = Set<String>()
            let picks = response.content.picks.compactMap { pick -> ForYouSuggestion? in
                guard let candidate = byID[pick.id.trimmingCharacters(in: .whitespaces)], seen.insert(candidate.id).inserted else { return nil }
                let reason = pick.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return ForYouModel.suggestion(candidate, reason: reason.isEmpty ? candidate.reason : reason)
            }
            let headline = response.content.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !picks.isEmpty, !headline.isEmpty else { return nil }
            return (headline, picks)
        } catch {
            Logger(subsystem: "com.vexrank.app", category: "ForYou").error("Apple Intelligence overview failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
#endif
