import SwiftUI
import Charts
import VEXRankKit

/// The season's rating line, drawn growing from nothing the first time it is
/// scrolled to - the web app's scroll-triggered curve.
///
/// Driven by a `TimelineView` rather than `withAnimation`: SwiftUI cannot
/// interpolate an array of chart data, so the frames are computed from elapsed
/// time and the series is recut on each one.
@available(iOS 17.0, *)
struct GrowingRatingChart: View {
    let history: [RatingPoint]
    let accent: Color

    private static let duration: Double = 1.25

    @State private var start: Date?
    @Environment(\.revealViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let start {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    chart(progress: RatingCurve.eased(elapsed / Self.duration))
                }
            } else {
                // Axes from the first frame, so the box holds its height and
                // nothing below it jumps when the curve arrives.
                chart(progress: 0)
            }
        }
        .background(trigger)
    }

    private func chart(progress: Double) -> some View {
        let samples = RatingCurve.growing(history, progress: progress)
        return Chart {
            ForEach(samples) { sample in
                LineMark(x: .value("Event", sample.date), y: .value("Rating", sample.rating))
                    .foregroundStyle(accent)
                    .interpolationMethod(.monotone)
            }
            // Only settled events get a dot; the moving tip is not an event.
            ForEach(samples.filter(\.isEvent)) { sample in
                PointMark(x: .value("Event", sample.date), y: .value("Rating", sample.rating))
                    .foregroundStyle(accent)
                    .symbolSize(28)
            }
        }
        .chartYScale(domain: RatingCurve.ratingDomain(history))
        .chartXScale(domain: RatingCurve.dateDomain(history) ?? Date()...Date())
    }

    private var trigger: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(of: geometry.frame(in: .global).minY, initial: true) { _, top in
                    guard start == nil else { return }
                    guard !reduceMotion else { start = .distantPast; return }
                    let line = viewportHeight > 0 ? viewportHeight * 0.88 : .greatestFiniteMagnitude
                    if top < line { start = .now }
                }
        }
    }
}
