import Foundation

/// The growing rating curve, as data rather than as a mask.
///
/// The obvious way to animate a line chart is to mask it and slide the mask
/// across, but a mask hides the axes and the labels along with the line, so the
/// box visibly reflows as it is revealed. The web app instead drew the axes
/// immediately and animated only the curve, and this does the same by feeding
/// the chart a shortened series: the axes come from a fixed domain, so they are
/// there from the first frame while the line grows into them.
public struct CurveSample: Identifiable, Sendable, Hashable {
    public let id: Int
    public let date: Date
    public let rating: Double
    /// False for the moving tip, which sits between two events and is not one.
    public let isEvent: Bool
}

public enum RatingCurve {
    /// The series truncated at `progress` (0...1), with the segment in progress
    /// cut part-way so the line advances smoothly instead of jumping a whole
    /// event at a time.
    public static func growing(_ history: [RatingPoint], progress: Double) -> [CurveSample] {
        let dated = history
            .compactMap { point in point.date.map { (date: $0, rating: Double(point.rating)) } }
            .sorted { $0.date < $1.date }
        guard dated.count > 1 else {
            return dated.enumerated().map {
                CurveSample(id: $0.offset, date: $0.element.date, rating: $0.element.rating, isEvent: true)
            }
        }

        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return [] }

        let position = clamped * Double(dated.count - 1)
        let whole = min(dated.count - 1, Int(position))
        var samples = dated.prefix(whole + 1).enumerated().map {
            CurveSample(id: $0.offset, date: $0.element.date, rating: $0.element.rating, isEvent: true)
        }

        let fraction = position - Double(whole)
        if fraction > 0, whole + 1 < dated.count {
            let from = dated[whole]
            let to = dated[whole + 1]
            samples.append(CurveSample(
                id: whole + 1,
                date: from.date.addingTimeInterval(to.date.timeIntervalSince(from.date) * fraction),
                rating: from.rating + (to.rating - from.rating) * fraction,
                isEvent: false
            ))
        }
        return samples
    }

    /// The fixed axis domains, taken from the whole series so they do not move
    /// while the curve grows. The padding matches the web's 15% of the spread,
    /// with a floor so a flat season is not drawn on a hairline.
    public static func ratingDomain(_ history: [RatingPoint]) -> ClosedRange<Double> {
        let ratings = history.map { Double($0.rating) }
        guard let low = ratings.min(), let high = ratings.max() else { return 0...1 }
        let padding = max(15, (high - low) * 0.15)
        return (low - padding)...(high + padding)
    }

    public static func dateDomain(_ history: [RatingPoint]) -> ClosedRange<Date>? {
        let dates = history.compactMap(\.date).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        // A single-event season has no span; give it one so the axis is valid.
        guard first < last else { return first.addingTimeInterval(-86400)...last.addingTimeInterval(86400) }
        return first...last
    }

    /// Ease-out: the curve arrives quickly and settles, which reads as drawn
    /// rather than as mechanically swept.
    public static func eased(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 1 - pow(1 - clamped, 3)
    }
}
