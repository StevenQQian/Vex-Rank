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
    /// Set once the curve has fully drawn. The timeline is then paused: left
    /// running, it recut and redrew the whole chart every frame for as long
    /// as the profile stayed open - a third of a core, doing nothing.
    @State private var finished = false
    @Environment(\.revealViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let start {
                TimelineView(.animation(paused: finished)) { timeline in
                    let elapsed = finished ? Self.duration : timeline.date.timeIntervalSince(start)
                    chart(progress: RatingCurve.eased(elapsed / Self.duration))
                }
                .task(id: start) {
                    try? await Task.sleep(for: .seconds(max(0, Self.duration - Date.now.timeIntervalSince(start)) + 0.05))
                    finished = true
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
        let labels = RatingCurve.axisLabels(history)
        let floor = RatingCurve.ratingDomain(history).lowerBound
        return Chart {
            // A wash of the accent under the line, fading to nothing at the
            // axis, so the season reads as a shape before it is read as dots.
            ForEach(samples) { sample in
                AreaMark(x: .value("Event", sample.x),
                         yStart: .value("Floor", floor),
                         yEnd: .value("Rating", sample.rating))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(samples) { sample in
                LineMark(x: .value("Event", sample.x), y: .value("Rating", sample.rating))
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            // Only settled events get a dot; the moving tip is not an event.
            // Green for a gain and rose for a loss, as on the web.
            ForEach(samples.filter(\.isEvent)) { sample in
                PointMark(x: .value("Event", sample.x), y: .value("Rating", sample.rating))
                    .foregroundStyle(sample.change >= 0 ? Color.win : Color.loss)
                    .symbolSize(52)
            }
        }
        .chartYScale(domain: RatingCurve.ratingDomain(history))
        .chartXScale(domain: RatingCurve.eventDomain(history))
        // Horizontal rules only, matching the web's `vertical={false}` grid.
        .chartXAxis {
            AxisMarks(values: labels.map(\.x)) { mark in
                AxisValueLabel {
                    // fixedSize, or Charts squeezes the last label - which sits
                    // nearest the edge - down to a single character.
                    Text(labels.first { $0.x == mark.as(Double.self) }?.label ?? "")
                        .font(.caption2)
                        .fixedSize()
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel().font(.caption2)
            }
        }
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
