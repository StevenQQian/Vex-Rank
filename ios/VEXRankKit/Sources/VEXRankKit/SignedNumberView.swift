#if canImport(SwiftUI)
import SwiftUI

/// Writes a team number one stroke at a time, in stroke order, at a constant
/// pen speed that eases off toward the final character.
///
/// Uses `Path.trim(from:to:)` rather than the web's stroke-dasharray. `trim` is
/// the direct equivalent and is better behaved: at 0 it draws genuinely
/// nothing, whereas a zero-length dash with a round cap paints a dot - the
/// defect that left a mark on the Y before it was written.
@available(iOS 17.0, macOS 14.0, *)
public struct SignedNumberView: View {
    private let text: String
    private let accentFrom: Int?
    private let accent: Color
    private let ink: Color

    /// Ordered strokes across the whole string, each tagged with the index of
    /// the character it belongs to.
    private let strokes: [(character: Int, path: String)]

    public init(text: String, accentFrom: Int? = nil, ink: Color = .primary, accent: Color = .red) {
        self.text = text
        self.accentFrom = accentFrom
        self.ink = ink
        self.accent = accent
        var collected: [(Int, String)] = []
        for (index, character) in Array(text).enumerated() {
            for stroke in StrokeGlyphs.strokes(for: character) ?? [] {
                collected.append((index, stroke))
            }
        }
        self.strokes = collected.map { (character: $0.0, path: $0.1) }
    }

    @State private var progress: [Double] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var characterCount: Int { Array(text).count }

    public var body: some View {
        if !StrokeGlyphs.canDraw(text) {
            // Falls back to text rather than rendering a gap.
            Text(text).font(.system(size: 44, weight: .semibold, design: .rounded))
        } else {
            Canvas { context, size in
                let unit = size.height / StrokeGlyphs.height
                for (index, stroke) in strokes.enumerated() {
                    let drawn = progress.indices.contains(index) ? progress[index] : 1
                    guard drawn > 0 else { continue }
                    let transform = CGAffineTransform(translationX: CGFloat(Double(stroke.character) * StrokeGlyphs.advance), y: 0)
                        .concatenating(CGAffineTransform(scaleX: unit, y: unit))
                    let placed = StrokePathParser.parse(stroke.path).path.applying(transform)
                    let colour = (accentFrom.map { stroke.character >= $0 } ?? false) ? accent : ink
                    context.stroke(
                        placed.trimmedPath(from: 0, to: drawn),
                        with: .color(colour),
                        style: StrokeStyle(lineWidth: 7 * unit, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .aspectRatio(CGFloat(Double(characterCount) * StrokeGlyphs.advance / StrokeGlyphs.height), contentMode: .fit)
            .accessibilityHidden(true)
            .onAppear(perform: write)
        }
    }

    private func write() {
        guard progress.isEmpty else { return }
        guard !reduceMotion else {
            progress = Array(repeating: 1, count: strokes.count)
            return
        }
        progress = Array(repeating: 0, count: strokes.count)

        // Matches the web timing: 0.92ms per glyph unit at the start, with the
        // pen easing off through the final character. The curve is keyed to the
        // character, not the stroke, because a hand slows through the whole of
        // the last character rather than only its last stroke.
        let penSpeed = 0.00092
        let penLift = 0.056
        let finalDrag = 1.35
        let lastCharacter = Double(max(1, characterCount - 1))

        var delay = 0.18
        for (index, stroke) in strokes.enumerated() {
            let through = Double(stroke.character) / lastCharacter
            let drag = 1 + finalDrag * pow(through, 1.7)
            let length = StrokePathParser.parse(stroke.path).approximateLength
            let duration = max(0.12, length * penSpeed * drag)
            withAnimation(.timingCurve(0.32, 0, 0.35, 1, duration: duration).delay(delay)) {
                progress[index] = 1
            }
            delay += duration + penLift * drag
        }
    }
}
#endif
