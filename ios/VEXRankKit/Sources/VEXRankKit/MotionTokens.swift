#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app's motion, in one place, so every screen moves with the same hand.
///
/// Springs throughout: they can be interrupted mid-flight and settle from
/// wherever they are, which a timed curve cannot. Feedback is quick, arrivals
/// are a little slower and softer, and nothing bounces enough to read as play.
@available(iOS 17.0, macOS 14.0, *)
public enum VEXMotion {
    /// A press acknowledged: under the finger and back.
    public static let press = Animation.spring(duration: 0.22, bounce: 0.3)
    /// A state change in place - a toggle, a filled star, a count ticking over.
    public static let snap = Animation.spring(duration: 0.35, bounce: 0.18)
    /// Content arriving - a section, a list's first rows.
    public static let arrive = Animation.spring(duration: 0.55, bounce: 0.08)

    /// Delay for the `index`th row of a list arriving, capped so a long list
    /// does not keep the reader waiting for the rows they can already see.
    public static func stagger(_ index: Int) -> Double { Double(min(index, 10)) * 0.035 }
}

/// Cards that are links sink a touch under the finger and spring back - the
/// same acknowledgement the chips give - instead of `.plain`'s nothing.
/// Reduce Motion gets a dim instead of the movement. A disabled control
/// fades, since a custom style otherwise looks exactly as tappable as before.
@available(iOS 17.0, macOS 14.0, *)
public struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? (reduceMotion ? 0.6 : 0.85) : 1)
            .animation(VEXMotion.press, value: configuration.isPressed)
            .animation(VEXMotion.snap, value: isEnabled)
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    /// Grows the area that takes a tap without growing the layout: the
    /// control keeps its drawn size and place, and a thumb landing up to
    /// `horizontal`/`vertical` points outside it still counts. For small
    /// controls set into text - a play glyph beside a match name, a team
    /// number pill - where a 44pt frame would push the row apart.
    public func hitArea(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .contentShape(Rectangle())
            .padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
    }
}

/// Taps you can feel, for the actions a sensory-feedback trigger cannot
/// see: a menu item chosen, a stream jumped. Called from the action itself,
/// so they only ever follow a person's touch, never a load or a refresh.
public enum Haptics {
    @MainActor public static func selection() {
        #if canImport(UIKit) && !os(watchOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    @MainActor public static func tap() {
        #if canImport(UIKit) && !os(watchOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension ButtonStyle where Self == PressableStyle {
    public static var pressable: PressableStyle { PressableStyle() }
}

/// A list's rows rising into place in order when the list first arrives.
///
/// Driven by one flag the list owns rather than by each row's own appearance:
/// a list recycles rows as it scrolls, and a row that animated on every
/// `onAppear` would rise again each time it came back on screen. Rows made
/// after the flag is set are simply there.
@available(iOS 17.0, macOS 14.0, *)
private struct Entrance: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : VEXMotion.arrive.delay(VEXMotion.stagger(index)),
                       value: shown)
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    /// Rises into place, in order, the first time `shown` turns true.
    public func entrance(_ index: Int, shown: Bool) -> some View {
        modifier(Entrance(index: index, shown: shown))
    }
}

/// A live marker's dot, breathing slowly so a running event is the one thing
/// in a list that moves. Still under Reduce Motion.
@available(iOS 17.0, macOS 14.0, *)
public struct LiveDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat

    public init(size: CGFloat = 6) { self.size = size }

    public var body: some View {
        Circle()
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(lineWidth: 1.5)
                    .scaleEffect(on ? 2.6 : 1)
                    .opacity(on ? 0 : 0.7)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true }
            }
            .accessibilityHidden(true)
    }
}
#endif
