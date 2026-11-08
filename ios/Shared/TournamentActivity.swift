import ActivityKit
import SwiftUI

/// Tournament mode's Live Activity: the Lock Screen card and the Dynamic
/// Island. Compiled into both the app, which starts and updates it, and the
/// widget extension, which draws it - ActivityKit pairs the two by this
/// type's name, so it lives in one file both targets build rather than in
/// VEXRankKit, which the extension does not link.
struct TournamentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "waiting", "running" or "done" - `TournamentStatus.Phase`.
        var phase: String
        /// The match on the field, or the one it is waiting to start.
        var currentLabel: String?
        var currentStarted: Date?
        var currentScheduled: Date?
        /// The team's next qualifier.
        var nextLabel: String?
        /// "red" or "blue": the plates the team will be wearing. Nil for VEX IQ.
        var nextAlliance: String?
        /// Who the team plays it with - for VEX IQ, which has no plates, the
        /// line the alliance colour takes in V5.
        var nextPartners: [String]?
        var nextField: String?
        var nextScheduled: Date?
        /// The schedule moved by however late the event is running.
        var nextEstimated: Date?
        var matchesUntil: Int?
        var updated: Date
    }

    var team: String
    var eventName: String
    var eventID: String
}

extension TournamentActivityAttributes.ContentState {
    var isDone: Bool { phase == "done" }
    var isTeamUp: Bool { matchesUntil == 0 }

    /// The colour of the team's next alliance, brightened from the app's
    /// alliance fills so it reads as text on the black of the Lock Screen and
    /// the Dynamic Island. White where there is no alliance to show.
    var allianceColour: Color {
        switch nextAlliance {
        case "red": return Color(red: 1.0, green: 0.36, blue: 0.39)
        case "blue": return Color(red: 0.43, green: 0.61, blue: 1.0)
        default: return .white
        }
    }

    var allianceName: String? {
        switch nextAlliance {
        case "red": return "Red alliance"
        case "blue": return "Blue alliance"
        default: return nil
        }
    }

    /// "Red alliance" in V5; "With 1234B" for a VEX IQ teamwork match.
    var sideLine: String? {
        if let name = allianceName { return name }
        guard let partners = nextPartners, !partners.isEmpty else { return nil }
        return "With " + partners.joined(separator: ", ")
    }
}
