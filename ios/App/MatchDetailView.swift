import SwiftUI
import VEXRankKit

/// One elimination match, opened from the bracket.
///
/// The bracket card has room for six team numbers and two scores, and a slot
/// can hold more than one game. This is where the rest of it goes: every game
/// in the slot, and every team on both alliances as a way through to their
/// profile.
@available(iOS 17.0, *)
struct MatchDetailView: View {
    let ref: MatchRef
    @Environment(\.vexTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(Array(ref.games.enumerated()), id: \.element.id) { index, game in
                    gameCard(game, number: index + 1, of: ref.games.count)
                }
            }
            .padding(16)
        }
        .background(theme.page)
        .navigationTitle(ref.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let division = ref.division {
                Text(division.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(1.4)
                    .foregroundStyle(.secondary)
            }
            if let series = ref.series {
                // A final is a series, so the series score leads and the
                // individual games sit underneath it.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(series.redWins)").foregroundStyle(Color.allianceRed)
                    Text(":").foregroundStyle(.secondary)
                    Text("\(series.blueWins)").foregroundStyle(Color.allianceBlue)
                }
                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                Text("Best of \(max(3, series.redWins + series.blueWins)) · \(ref.games.count) played")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func gameCard(_ game: DivisionMatch, number: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(game.name ?? (total > 1 ? "Game \(number)" : ref.title))
                    .font(.caption.weight(.semibold))
                Spacer()
                if let field = game.field, !field.isEmpty {
                    Text(field).font(.caption2).foregroundStyle(.secondary)
                }
                if let time = game.scheduled.flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            if game.isPlayed, let red = game.red?.score, let blue = game.blue?.score {
                ScoreSplit(red: red, blue: blue)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider().overlay(Color.hairline)
            alliance(game.red, colour: .allianceRed, label: "RED",
                     won: game.winner == "red", decided: game.winner != nil, played: game.isPlayed)
            Divider().overlay(Color.hairline)
            alliance(game.blue, colour: .allianceBlue, label: "BLUE",
                     won: game.winner == "blue", decided: game.winner != nil, played: game.isPlayed)

            if !game.isPlayed {
                Text("NOT YET PLAYED")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            } else if game.winner == nil {
                Text("TIED").font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func alliance(_ alliance: MatchAlliance?, colour: Color, label: String,
                          won: Bool, decided: Bool, played: Bool) -> some View {
        let numbers = alliance?.numbers ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AllianceTag(isRed: label == "RED")
                Spacer()
                Text(alliance?.score.map(String.init) ?? "—")
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(won ? Color.win : Color.primary)
            }

            // Each number is its own link. Tapping the alliance as a whole would
            // have to guess which of three teams was meant.
            FlowRow(spacing: 8) {
                ForEach(numbers, id: \.self) { number in
                    NavigationLink(value: TeamRef(number)) {
                        HStack(spacing: 4) {
                            Text(number)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            StrokeIcon(.chevronRight, size: 9, relativeTo: .caption2)
                                .foregroundStyle(.subtle)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(theme.surfaceRaised, in: Capsule())
                        // A 30pt pill; the FlowRow's 8pt gaps leave room to
                        // reach 44 without overlapping a neighbour much.
                        .hitArea(horizontal: 4, vertical: 7)
                    }
                    .buttonStyle(.pressable)
                }
                if numbers.isEmpty {
                    Text("Not posted").font(.caption).foregroundStyle(.subtle)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(decided && !won ? 0.55 : 1)
        .background(won ? Color.win.opacity(0.12) : .clear)
    }
}

/// Wraps its children onto as many lines as they need.
///
/// An alliance is three numbers, and three of the longer ones do not fit a
/// phone's width on one line - an HStack would shrink them all to fit rather
/// than move one down.
@available(iOS 17.0, *)
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty && needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The two scores as one bar split between the alliances, the winner's side
/// longer: the margin as a shape. Swings in from the middle when it appears.
@available(iOS 17.0, *)
private struct ScoreSplit: View {
    let red: Int
    let blue: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = max(1, red + blue)
        let share = shown ? Double(red) / Double(total) : 0.5
        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.allianceRed).frame(width: max(0, (geo.size.width - 2) * share))
                    Rectangle().fill(Color.allianceBlue)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack {
                Text("\(Int((Double(red) / Double(total) * 100).rounded()))%")
                Spacer()
                Text("Margin \(abs(red - blue))").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((Double(blue) / Double(total) * 100).rounded()))%")
            }
            .font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.15)) { shown = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Red \(red), blue \(blue), margin \(abs(red - blue))")
    }
}
