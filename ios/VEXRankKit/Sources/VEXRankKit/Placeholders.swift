#if canImport(SwiftUI)
import SwiftUI

// Loading screens drawn in the shape of what is coming - rows where the rows
// will be, a ring where the ring will be - instead of a spinner on an empty
// page. The reader sees the layout before the data, nothing jumps when it
// lands, and the wait reads as shorter than it is.

/// A band of light sweeping across whatever it is applied to, masked to that
/// view's own shapes. Still under Reduce Motion.
@available(iOS 17.0, macOS 14.0, *)
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let band = max(geo.size.width * 0.5, 120)
                        LinearGradient(colors: [.clear, .white.opacity(0.09), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (geo.size.width + band))
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    public func shimmering() -> some View { modifier(Shimmer()) }

    /// Marks a placeholder as one "Loading" element for VoiceOver, rather
    /// than a run of unlabelled shapes.
    public func loadingPlaceholder() -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One grey shape standing in for a piece of text or a figure.
@available(iOS 17.0, macOS 14.0, *)
public struct PlaceholderBlock: View {
    private let width: CGFloat?
    private let height: CGFloat
    private let radius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = 12, radius: CGFloat = 5) {
        self.width = width
        self.height = height
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A list row's worth of placeholder: an optional badge, two or three lines
/// of text, and an optional figure on the right - the shape of a ranking,
/// event or match row.
@available(iOS 17.0, macOS 14.0, *)
public struct PlaceholderRow: View {
    private let badge: Bool
    private let lines: Int
    private let trailing: Bool
    private let seed: Int

    /// `seed` varies the line lengths so a column of rows does not read as
    /// one repeated stamp.
    public init(badge: Bool = true, lines: Int = 3, trailing: Bool = true, seed: Int = 0) {
        self.badge = badge
        self.lines = lines
        self.trailing = trailing
        self.seed = seed
    }

    private static let widths: [CGFloat] = [0.55, 0.8, 0.4, 0.7, 0.62, 0.48, 0.75]

    public var body: some View {
        HStack(spacing: 14) {
            if badge { PlaceholderBlock(width: 32, height: 32, radius: 10) }
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<lines, id: \.self) { line in
                        PlaceholderBlock(width: geo.size.width * width(line),
                                         height: line == 0 ? 15 : 11)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: CGFloat(lines) * 18)
            if trailing {
                VStack(alignment: .trailing, spacing: 6) {
                    PlaceholderBlock(width: 52, height: 18)
                    PlaceholderBlock(width: 30, height: 9)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func width(_ line: Int) -> CGFloat {
        let base = Self.widths[(seed * 3 + line) % Self.widths.count]
        return line == 0 ? min(base + 0.15, 0.9) : base
    }
}

/// A whole list of placeholder rows on the page background, for a screen
/// whose first load is still on its way.
@available(iOS 17.0, macOS 14.0, *)
public struct PlaceholderList: View {
    @Environment(\.vexTheme) private var theme
    private let rows: Int
    private let badge: Bool
    private let lines: Int
    private let trailing: Bool
    private let caption: String?

    public init(rows: Int = 9, badge: Bool = true, lines: Int = 3, trailing: Bool = true, caption: String? = nil) {
        self.rows = rows
        self.badge = badge
        self.lines = lines
        self.trailing = trailing
        self.caption = caption
    }

    public var body: some View {
        // Not scrollable: there is nothing to scroll to yet, and a drag on
        // it would only rubber-band.
        VStack(alignment: .leading, spacing: 0) {
            if let caption {
                Text(caption).font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }
            ForEach(0..<rows, id: \.self) { row in
                PlaceholderRow(badge: badge, lines: lines, trailing: trailing, seed: row)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 16)
            }
            Spacer(minLength: 0)
        }
        // The sweep is masked to the shapes, so it goes on before the
        // surface does - after, it would wash the whole page.
        .shimmering()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface)
        .loadingPlaceholder()
    }
}
#endif
