#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app's own icons: single-stroke drawings in the hand the team numbers
/// are written in - one even, round-capped pen, centreline paths - rather
/// than SF Symbols, whose filled, optically weighted shapes belong to every
/// other app on the phone.
///
/// Each icon is the same small SVG subset the glyphs use (`M`, `L`, `C`, `Z`,
/// parsed by `StrokePathParser`) on a 24-unit grid, so an icon can be drawn
/// on the way a number is: by trimming its path from 0 to 1.
///
/// A dot is a zero-length segment (`M12,8 L12,8.1`); the round cap makes it.
///
/// Two habits make them the app's rather than a stock set: rings are drawn
/// open, the pen lifting just before it closes the loop the way a marker
/// circles something, and the subjects are the sport's - a robot for a team,
/// a numbered podium for a ranking.
public enum VEXIcon: String, CaseIterable, Sendable {
    case podium, robot, trophy, calendar, stats, team, info, settings, offline, filter, close
    case star, starFilled, starSlash, pin, chevronUpDown, chevronRight, chevronDown
    case globe, map, external, list, plus, play, stream, live, clock, check, flag
    case warning, download, megaphone, divisions, sort, compass, grade

    /// Strokes in drawing order.
    var strokes: [String] {
        switch self {
        case .podium:
            return ["M2.5,20 L21.5,20", "M9,20 L9,7.5 L15,7.5 L15,20", "M9,12 L3.5,12 L3.5,20",
                    "M15,14.5 L20.5,14.5 L20.5,20", "M11,11 L12.3,10 L12.3,15"]
        case .robot:
            return [Self.box(5, 8, 19, 19.5), "M12,8 L12,5", "M12,3.4 L12,3.5",
                    "M9.5,12.8 L9.5,12.9", "M14.5,12.8 L14.5,12.9", "M9.5,16 L14.5,16",
                    "M2.8,12 L2.8,15.5", "M21.2,12 L21.2,15.5"]
        case .trophy:
            return ["M7,4 L17,4 L17,9 C17,12.8 14.8,15 12,15 C9.2,15 7,12.8 7,9 Z",
                    "M7,6 L4.5,6 C4.5,9.4 5.6,11 7.6,11.6",
                    "M17,6 L19.5,6 C19.5,9.4 18.4,11 16.4,11.6",
                    "M12,15 L12,19", "M8,20 L16,20"]
        case .calendar:
            return [Self.box(4, 6, 20, 20), "M4,10.5 L20,10.5", "M8.5,3.5 L8.5,7.5", "M15.5,3.5 L15.5,7.5",
                    "M8,14.5 L8,14.6", "M12,14.5 L12,14.6", "M16,14.5 L16,14.6"]
        case .stats:
            return ["M5,20 L5,14", "M10,20 L10,8", "M15,20 L15,11.5", "M20,20 L20,4.5"]
        case .team:
            return [Self.circle(9, 8, 3),
                    "M3.5,19.5 C3.5,15.8 6,13.6 9,13.6 C12,13.6 14.5,15.8 14.5,19.5",
                    "M15.6,5.6 C17.3,5.2 19,6.5 19,8.4 C19,10.3 17.3,11.6 15.6,11.2",
                    "M16.8,13.8 C19,14.2 20.5,16 20.5,19"]
        case .info:
            return [Self.circle(12, 12, 9), "M12,11 L12,16.5", "M12,7.7 L12,7.8"]
        case .settings:
            return ["M4,7 L7,7", "M11,7 L20,7", Self.circle(9, 7, 2),
                    "M4,17 L13,17", "M17,17 L20,17", Self.circle(15, 17, 2)]
        case .offline:
            return ["M4.6,10.2 C8.8,6.4 15.2,6.4 19.4,10.2",
                    "M7.8,13.6 C10.3,11.5 13.7,11.5 16.2,13.6",
                    "M12,17.5 L12,17.6", "M4.5,4.5 L19.5,19.5"]
        case .filter:
            return ["M4,5 L20,5 L14,12.5 L14,19 L10,17 L10,12.5 Z"]
        case .close:
            return ["M6.5,6.5 L17.5,17.5", "M17.5,6.5 L6.5,17.5"]
        case .star, .starFilled:
            return [Self.starPath]
        case .starSlash:
            return [Self.starPath, "M4,4 L20,20"]
        case .pin:
            return ["M12,21 C12,21 5,14.6 5,9.6 C5,5.7 8.1,3 12,3 C15.9,3 19,5.7 19,9.6 C19,14.6 12,21 12,21 Z",
                    Self.circle(12, 9.6, 2.4)]
        case .chevronUpDown:
            return ["M8,9.5 L12,5.5 L16,9.5", "M8,14.5 L12,18.5 L16,14.5"]
        case .chevronRight:
            return ["M9.5,6 L15.5,12 L9.5,18"]
        case .chevronDown:
            return ["M6,9.5 L12,15.5 L18,9.5"]
        case .globe:
            return [Self.circle(12, 12, 9), "M3,12 L21,12",
                    "M12,3 C8.2,7 8.2,17 12,21", "M12,3 C15.8,7 15.8,17 12,21"]
        case .map:
            return ["M3.5,6 L9,4 L15,6 L20.5,4 L20.5,18 L15,20 L9,18 L3.5,20 Z", "M9,4 L9,18", "M15,6 L15,20"]
        case .external:
            return ["M7.5,16.5 L16.5,7.5", "M9.5,7.5 L16.5,7.5 L16.5,14.5"]
        case .list:
            return ["M5,7 L5,7.1", "M9,7 L19,7", "M5,12 L5,12.1", "M9,12 L19,12", "M5,17 L5,17.1", "M9,17 L19,17"]
        case .plus:
            return ["M12,5 L12,19", "M5,12 L19,12"]
        case .play:
            return ["M8,5 L18.5,12 L8,19 Z"]
        case .stream:
            return [Self.box(3.5, 5.5, 20.5, 18.5), "M10.5,9.5 L14.5,12 L10.5,14.5 Z"]
        case .live:
            return ["M12,12 L12,12.1",
                    "M8.6,8.6 C6.7,10.5 6.7,13.5 8.6,15.4", "M15.4,8.6 C17.3,10.5 17.3,13.5 15.4,15.4",
                    "M5.5,5.5 C2,9 2,15 5.5,18.5", "M18.5,5.5 C22,9 22,15 18.5,18.5"]
        case .clock:
            return [Self.circle(12, 12, 9), "M12,7 L12,12 L15.5,14"]
        case .check:
            return ["M5,12.5 L10,17.5 L19,7"]
        case .flag:
            return ["M5.5,21 L5.5,4", "M5.5,4.5 C9,2.8 12,6.4 18.5,4.5 L18.5,13 C12,14.9 9,11.3 5.5,13"]
        case .warning:
            return ["M12,3.5 L21,19.5 L3,19.5 Z", "M12,9.5 L12,13.5", "M12,16.6 L12,16.7"]
        case .download:
            return [Self.circle(12, 12, 9), "M12,7.5 L12,16", "M8.5,12.5 L12,16 L15.5,12.5"]
        case .megaphone:
            return ["M4,10 L4,14 L8,14 L17,19 L17,5 L8,10 Z", "M8,14 L9.2,19.5", "M20,10 L20,14"]
        case .divisions:
            return [Self.box(4, 5, 20, 19), "M12,5 L12,19"]
        case .sort:
            return ["M8,19 L8,5", "M4.5,8.5 L8,5 L11.5,8.5", "M16,5 L16,19", "M12.5,15.5 L16,19 L19.5,15.5"]
        case .compass:
            return [Self.circle(12, 12, 9), "M15.5,8.5 L13.3,13.3 L8.5,15.5 L10.7,10.7 Z"]
        case .grade:
            return ["M2.5,9 L12,4.5 L21.5,9 L12,13.5 Z", "M6.5,11 L6.5,15.5 C9,18.2 15,18.2 17.5,15.5 L17.5,11",
                    "M21.5,9 L21.5,14"]
        }
    }

    /// Drawn filled as well as stroked: the solid forms, where the filled
    /// state is the meaning (a starred team, the play control).
    public var isFilled: Bool { self == .starFilled || self == .play }

    // MARK: - Path helpers

    /// A box with softened corners - the pen turning, not a ruled square.
    private static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, r: Double = 2.5) -> String {
        "M\(x0 + r),\(y0) L\(x1 - r),\(y0) C\(x1 - r * 0.45),\(y0) \(x1),\(y0 + r * 0.45) \(x1),\(y0 + r) "
            + "L\(x1),\(y1 - r) C\(x1),\(y1 - r * 0.45) \(x1 - r * 0.45),\(y1) \(x1 - r),\(y1) "
            + "L\(x0 + r),\(y1) C\(x0 + r * 0.45),\(y1) \(x0),\(y1 - r * 0.45) \(x0),\(y1 - r) "
            + "L\(x0),\(y0 + r) C\(x0),\(y0 + r * 0.45) \(x0 + r * 0.45),\(y0) \(x0 + r),\(y0) Z"
    }

    /// A ring, left open at the upper right: drawn clockwise from just past
    /// the gap to just before it, in four cubic arcs. Small rings (a slider's
    /// knob, a pin's centre) close, since a gap that size reads as a flaw.
    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        let gap = r >= 5 ? 34.0 : 0
        let start = (-45 + gap / 2) * Double.pi / 180
        let sweep = (360 - gap) * Double.pi / 180
        let step = sweep / 4
        let k = 4.0 / 3 * tan(step / 4) * r
        func point(_ a: Double) -> (Double, Double) { (cx + r * cos(a), cy + r * sin(a)) }
        func fmt(_ x: Double, _ y: Double) -> String { String(format: "%.3f,%.3f", x, y) }
        let first = point(start)
        var d = "M" + fmt(first.0, first.1)
        for i in 0..<4 {
            let a0 = start + Double(i) * step, a1 = a0 + step
            let p0 = point(a0), p1 = point(a1)
            d += " C" + fmt(p0.0 - k * sin(a0), p0.1 + k * cos(a0))
                + " " + fmt(p1.0 + k * sin(a1), p1.1 - k * cos(a1))
                + " " + fmt(p1.0, p1.1)
        }
        return gap == 0 ? d + " Z" : d
    }

    private static let starPath: String = {
        var points: [String] = []
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? 9.0 : 4.1
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            points.append(String(format: "%.2f,%.2f", 12 + radius * cos(angle), 12.8 + radius * sin(angle)))
        }
        return "M" + points[0] + points.dropFirst().map { " L" + $0 }.joined() + " Z"
    }()

    /// The parsed path in grid units, parsed once.
    fileprivate var path: Path { VEXIcon.cache[self]! }

    private static let cache: [VEXIcon: Path] = {
        var paths: [VEXIcon: Path] = [:]
        for icon in VEXIcon.allCases {
            var path = Path()
            for stroke in icon.strokes { path.addPath(StrokePathParser.parse(stroke).path) }
            paths[icon] = path
        }
        return paths
    }()

    /// Pen width on the 24-unit grid - the team number's pen, scaled down to
    /// an icon and thickened a touch so it holds up at caption size.
    static let penWidth: CGFloat = 1.9
}

/// The icon as a shape, scaled from its 24-unit grid into whatever square
/// it is given - so it can be trimmed, stroked and animated like any shape.
@available(iOS 17.0, macOS 14.0, *)
public struct VEXIconShape: Shape {
    public let icon: VEXIcon
    public init(_ icon: VEXIcon) { self.icon = icon }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        return icon.path.applying(
            CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale))
    }
}

/// An icon drawn in the app's pen, sized with Dynamic Type.
///
/// `drawsOn` writes it in, stroke by stroke, the first time it appears - the
/// way the team number is written on the profile - for the few icons that
/// carry a moment: an empty state, tournament mode switching on.
@available(iOS 17.0, macOS 14.0, *)
public struct StrokeIcon: View {
    private let icon: VEXIcon
    private let drawsOn: Bool
    @ScaledMetric private var size: CGFloat
    @State private var progress: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ icon: VEXIcon, size: CGFloat = 17, relativeTo style: Font.TextStyle = .body, drawsOn: Bool = false) {
        self.icon = icon
        self.drawsOn = drawsOn
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        _progress = State(initialValue: drawsOn ? 0 : 1)
    }

    public var body: some View {
        let shape = VEXIconShape(icon)
        let width = VEXIcon.penWidth * size / 24 * (size < 14 ? 1.15 : 1)
        ZStack {
            if icon.isFilled {
                shape.fill().opacity(Double(progress))
            }
            shape.trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard drawsOn, progress < 1 else { return }
            if reduceMotion { progress = 1; return }
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension Label where Title == Text, Icon == StrokeIcon {
    /// A label with one of the app's own icons in place of an SF Symbol.
    public init(_ title: String, icon: VEXIcon, size: CGFloat = 17, relativeTo style: Font.TextStyle = .body,
                drawsOn: Bool = false) {
        self.init { Text(title) } icon: { StrokeIcon(icon, size: size, relativeTo: style, drawsOn: drawsOn) }
    }
}

#if canImport(UIKit)
extension VEXIcon {
    /// The icon as a template image, for the places SwiftUI takes nothing but
    /// an image - tab items, and the labels of items inside a menu, which UIKit
    /// draws. Tinted by the system like a symbol would be.
    @MainActor
    public func image(size: CGFloat = 24, weight: CGFloat = 1) -> Image {
        let key = "\(rawValue)-\(size)-\(weight)"
        if let cached = VEXIcon.images[key] { return Image(uiImage: cached) }
        let scale = size / 24
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.addPath(path.cgPath)
            cg.setLineWidth(VEXIcon.penWidth * weight)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setFillColor(UIColor.black.cgColor)
            cg.drawPath(using: isFilled ? .fillStroke : .stroke)
        }.withRenderingMode(.alwaysTemplate)
        VEXIcon.images[key] = rendered
        return Image(uiImage: rendered)
    }

    @MainActor private static var images: [String: UIImage] = [:]
}
#endif
#endif
