#if canImport(SwiftUI)
import SwiftUI

// The small pictures the screens draw their numbers with: a ring for a share,
// a bar for a record, a line for a run of results. Each one draws itself in the
// first time it is scrolled to - never on every reappearance - and is simply
// there under Reduce Motion, so the figure is readable from the first frame
// either way.

/// Medal colours for the first three places, the same on every theme.
@available(iOS 17.0, macOS 14.0, *)
extension ShapeStyle where Self == Color {
    public static var gold: Color { Color(hex: 0xf5c451) }
    public static var silver: Color { Color(hex: 0xc9d1dc) }
    public static var bronze: Color { Color(hex: 0xd9905a) }

    /// Gold, silver or bronze for 1, 2 and 3; nil after that.
    public static func medal(_ place: Int) -> Color? {
        switch place {
        case 1: return .gold
        case 2: return .silver
        case 3: return .bronze
        default: return nil
        }
    }
}

/// Runs `action` once, the first time this view is on screen inside a scroll
/// view that publishes its viewport (`publishesRevealViewport`). Outside one
/// it runs on appear.
@available(iOS 17.0, macOS 14.0, *)
private struct FirstVisible: ViewModifier {
    let action: () -> Void
    @State private var fired = false
    @Environment(\.revealViewportHeight) private var viewportHeight

    func body(content: Content) -> some View {
        // Measured in the scroll view's own space, the same space the
        // published viewport height is in. Against the screen, the bars above
        // the scroll view pushed every position down by their height, and a
        // tile resting low on screen read as below the fold until scrolled.
        // The watcher sits in a background and is taken away once it has
        // fired, so a figure already drawn costs nothing per scroll frame -
        // and the content keeps its identity, since only the background
        // changes.
        content.background {
            if !fired {
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { top in
                    check(top)
                }
            }
        }
    }

    private func check(_ top: CGFloat) {
        guard !fired else { return }
        let line = viewportHeight > 0 ? viewportHeight * 0.92 : .greatestFiniteMagnitude
        guard top < line else { return }
        fired = true
        action()
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    public func onFirstVisible(_ action: @escaping () -> Void) -> some View {
        modifier(FirstVisible(action: action))
    }
}

/// Whether a drawing has been scrolled to yet, as a 0-to-1 progress that
/// springs up once. Shared by every figure below.
@available(iOS 17.0, macOS 14.0, *)
private struct DrawIn: ViewModifier {
    @Binding var progress: Double
    let delay: Double
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.onFirstVisible {
                if reduceMotion { progress = 1; return }
                withAnimation(.spring(duration: 1.0, bounce: 0.12).delay(delay)) { progress = 1 }
            }
        } else {
            content
        }
    }
}

/// A share drawn as a ring - a win rate, a percentile - with whatever the
/// caller puts in the middle.
@available(iOS 17.0, macOS 14.0, *)
public struct RingGauge<Centre: View>: View {
    private let fraction: Double
    private let colour: Color
    private let lineWidth: CGFloat
    private let delay: Double
    private let centre: Centre
    @State private var progress = 0.0

    public init(fraction: Double, colour: Color, lineWidth: CGFloat = 10, delay: Double = 0,
                @ViewBuilder centre: () -> Centre) {
        self.fraction = min(1, max(0, fraction))
        self.colour = colour
        self.lineWidth = lineWidth
        self.delay = delay
        self.centre = centre()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction * progress)
                .stroke(AngularGradient(colors: [colour.opacity(0.55), colour], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: colour.opacity(0.45), radius: 6)
            centre
        }
        .padding(lineWidth / 2)
        .modifier(DrawIn(progress: $progress, delay: delay))
    }
}

/// Won, lost and tied as one bar split in proportion: the shape of a record
/// at a glance, where "41-6-0" has to be read.
@available(iOS 17.0, macOS 14.0, *)
public struct RecordBar: View {
    private let wins: Int
    private let losses: Int
    private let ties: Int
    private let height: CGFloat
    @State private var progress = 0.0

    public init(wins: Int, losses: Int, ties: Int, height: CGFloat = 8) {
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let total = max(1, wins + losses + ties)
            let gap: CGFloat = 2
            let usable = geo.size.width - gap * 2
            HStack(spacing: gap) {
                segment(.win, CGFloat(wins) / CGFloat(total) * usable)
                segment(.gray.opacity(0.7), CGFloat(ties) / CGFloat(total) * usable)
                segment(.loss, CGFloat(losses) / CGFloat(total) * usable)
            }
            .frame(width: geo.size.width * progress, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: height)
        .background(Color.white.opacity(0.06), in: Capsule())
        .modifier(DrawIn(progress: $progress, delay: 0.1))
        .accessibilityElement()
        .accessibilityLabel("\(wins) won, \(losses) lost, \(ties) tied")
    }

    private func segment(_ colour: Color, _ width: CGFloat) -> some View {
        Rectangle().fill(colour).frame(width: max(0, width))
    }
}

/// How far along a scale a value sits, as a filling capsule.
@available(iOS 17.0, macOS 14.0, *)
public struct LevelBar: View {
    private let fraction: Double
    private let colour: Color
    private let height: CGFloat
    private let delay: Double
    private let animated: Bool
    @State private var progress = 0.0

    /// `animated: false` for list rows: a List recycles its rows, so a bar
    /// that filled on arrival would refill on every scroll past, and each one
    /// would watch its own position while it waited.
    public init(fraction: Double, colour: Color, height: CGFloat = 6, delay: Double = 0, animated: Bool = true) {
        self.fraction = min(1, max(0, fraction))
        self.colour = colour
        self.height = height
        self.delay = delay
        self.animated = animated
        _progress = State(initialValue: animated ? 0 : 1)
    }

    public var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: [colour.opacity(0.6), colour], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(height, geo.size.width * fraction * progress))
                .opacity(progress > 0 ? 1 : 0)
        }
        .frame(height: height)
        .background(Color.white.opacity(0.07), in: Capsule())
        .modifier(DrawIn(progress: $progress, delay: delay, enabled: animated))
        .accessibilityHidden(true)
    }
}

/// A run of values as a small line with a soft fill under it, the last point
/// marked. Rising draws in `rising`, falling in `falling`.
@available(iOS 17.0, macOS 14.0, *)
public struct Sparkline: View {
    private let values: [Double]
    private let rising: Color
    private let falling: Color
    private let lineWidth: CGFloat
    private let animated: Bool
    @State private var progress = 0.0

    public init(_ values: [Double], rising: Color = .win, falling: Color = .loss,
                lineWidth: CGFloat = 1.6, animated: Bool = true) {
        self.values = values
        self.rising = rising
        self.falling = falling
        self.lineWidth = lineWidth
        self.animated = animated
    }

    private var colour: Color { (values.last ?? 0) >= (values.first ?? 0) ? rising : falling }

    public var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size, inset: lineWidth + 1.5)
            ZStack {
                Self.area(points, bottom: geo.size.height)
                    .fill(LinearGradient(colors: [colour.opacity(0.28), colour.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(animated ? progress : 1)
                Self.line(points)
                    .trim(from: 0, to: animated ? progress : 1)
                    .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(colour)
                        .frame(width: lineWidth * 2.6, height: lineWidth * 2.6)
                        .position(last)
                        .opacity(animated ? (progress > 0.95 ? 1 : 0) : 1)
                }
            }
        }
        .modifier(DrawIn(progress: $progress, delay: 0.05, enabled: animated))
        .accessibilityHidden(true)
    }

    static func points(_ values: [Double], in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        let span = max(high - low, 1)
        let width = size.width - inset * 2
        let height = size.height - inset * 2
        return values.enumerated().map { i, v in
            CGPoint(x: inset + width * CGFloat(i) / CGFloat(values.count - 1),
                    y: inset + height * CGFloat(1 - (v - low) / span))
        }
    }

    static func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
        }
    }

    static func area(_ points: [CGPoint], bottom: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: bottom))
            for p in points { path.addLine(to: p) }
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.closeSubpath()
        }
    }
}

/// A figure that counts up to its value the first time it is seen, digits
/// rolling, and rolls again whenever the value changes.
@available(iOS 17.0, macOS 14.0, *)
public struct CountingNumber: View {
    private let value: Int
    private let prefix: String
    private let suffix: String
    @State private var fired = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ value: Int, prefix: String = "", suffix: String = "") {
        self.value = value
        self.prefix = prefix
        self.suffix = suffix
    }

    public var body: some View {
        // Reads `value` at draw time, never a copy taken when it fired: a
        // figure that lands after the first look (a season's standings
        // arriving late) must show the new number, not the one it began with.
        let current = fired ? value : 0
        Text("\(prefix)\(current)\(suffix)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(current)))
            .animation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.05), value: current)
            .onFirstVisible { fired = true }
            .accessibilityLabel("\(prefix)\(value)\(suffix)")
    }
}

/// The backdrop behind a screen's opening block: a field's six-by-six tiles,
/// fading out from one corner, under a glow of the theme accent. Still: a
/// glow that drifted forever kept the header redrawing every frame of every
/// profile, for a movement nobody would miss.
@available(iOS 17.0, macOS 14.0, *)
public struct FieldBackdrop: View {
    private let accent: Color

    public init(accent: Color) { self.accent = accent }

    public var body: some View {
        ZStack {
            RadialGradient(colors: [accent.opacity(0.30), accent.opacity(0)],
                           center: UnitPoint(x: 0.75, y: 0.25),
                           startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(hex: 0x3f6fe0).opacity(0.16), .clear],
                           center: UnitPoint(x: 0.15, y: 0.85),
                           startRadius: 0, endRadius: 260)
            Canvas { context, size in
                let tile = size.width / 6
                let rows = Int(size.height / tile) + 1
                for row in 0...rows {
                    for column in 0..<6 {
                        let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                                          width: tile, height: tile).insetBy(dx: 1.5, dy: 1.5)
                        let fade = max(0, 1 - Double(row) / Double(max(rows, 1)) - Double(5 - column) * 0.08)
                        context.stroke(Path(roundedRect: rect, cornerRadius: 6),
                                       with: .color(.white.opacity(0.05 * fade)), lineWidth: 1)
                    }
                }
            }
        }
        .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        // Flattened to one layer, so scrolling moves a bitmap rather than
        // recompositing two gradients, a canvas and a mask each frame.
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A placing as a badge: gold, silver and bronze for the first three, the
/// accent for the rest of the top `highlight`, quiet after that.
@available(iOS 17.0, macOS 14.0, *)
public struct PlaceBadge: View {
    @Environment(\.vexTheme) private var theme
    private let place: Int
    private let size: CGFloat
    private let highlight: Int

    public init(_ place: Int, size: CGFloat = 36, highlight: Int = 8) {
        self.place = place
        self.size = size
        self.highlight = highlight
    }

    public var body: some View {
        let medal = Color.medal(place)
        let fill: Color = medal ?? (place <= highlight ? theme.accent.opacity(0.22) : theme.surfaceRaised)
        Text("\(place)")
            .font(.system(size: size * (place >= 100 ? 0.34 : 0.42), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(medal != nil ? Color.black.opacity(0.8) : place <= highlight ? theme.accent : .secondary)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .shadow(color: (medal ?? .clear).opacity(0.5), radius: 6)
            .accessibilityLabel("Place \(place)")
    }
}
#endif
