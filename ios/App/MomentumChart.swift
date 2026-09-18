import SwiftUI
import Charts
import VEXRankKit

/// A team's run through one tournament, drawn the way the season rating curve
/// is drawn: the line grows in when it first appears, on a fixed axis so
/// nothing reflows under it.
@available(iOS 17.0, *)
struct MomentumChart: View {
    let points: [MomentumPoint]
    let accent: Color

    private static let duration: Double = 1.1

    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let start {
                TimelineView(.animation) { timeline in
                    chart(progress: RatingCurve.eased(timeline.date.timeIntervalSince(start) / Self.duration))
                }
            } else {
                chart(progress: 0)
            }
        }
        .onAppear { start = reduceMotion ? .distantPast : .now }
    }

    private func chart(progress: Double) -> some View {
        let shown = visible(progress)
        return Chart {
            // Level is the reading that matters, so the line for it is drawn
            // whatever the data does.
            RuleMark(y: .value("Level", 0))
                .foregroundStyle(.white.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(shown) { point in
                LineMark(x: .value("Match", point.match), y: .value("Momentum", point.cumulative))
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(shown) { point in
                PointMark(x: .value("Match", point.match), y: .value("Momentum", point.cumulative))
                    .foregroundStyle(colour(point.outcome))
                    .symbolSize(50)
            }
        }
        .chartXScale(domain: 0.5...(Double(points.count) + 0.5))
        .chartYScale(domain: TeamMomentum.range(points))
        .chartXAxis {
            AxisMarks(values: Array(1...max(1, points.count))) { mark in
                AxisValueLabel {
                    Text("\(mark.as(Int.self) ?? 0)").font(.caption2).fixedSize()
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel().font(.caption2)
            }
        }
    }

    /// The points up to `progress`. Whole matches only: a momentum step is a
    /// result, and half a result is not a thing.
    private func visible(_ progress: Double) -> [MomentumPoint] {
        guard !points.isEmpty else { return [] }
        let shown = Int((min(1, max(0, progress)) * Double(points.count)).rounded(.up))
        return Array(points.prefix(max(0, shown)))
    }

    private func colour(_ outcome: TeamMatch.Outcome) -> Color {
        switch outcome {
        case .won: return Color(.sRGB, red: 0.20, green: 0.83, blue: 0.60)
        case .lost: return Color(.sRGB, red: 0.98, green: 0.44, blue: 0.52)
        default: return .gray
        }
    }
}
