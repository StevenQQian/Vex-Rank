import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
@main
struct VEXRankApp: App {
    @AppStorage("vexrank-theme") private var themeID: String = VEXTheme.midnight.id
    @State private var path = NavigationPath()

    /// `-team 31260X` opens straight to a profile. Used for verifying the
    /// profile without tapping, and the hook a URL scheme will reuse.
    private static var launchTeam: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "-team"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                RankingsListView()
                    .navigationTitle("World ranking")
                    .navigationDestination(for: String.self) { TeamProfileView(number: $0) }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Picker("Colour theme", selection: $themeID) {
                                    ForEach(VEXTheme.all) { Text($0.name).tag($0.id) }
                                }
                            } label: {
                                Image(systemName: "circle.lefthalf.filled")
                            }
                        }
                    }
            }
            .onAppear { if let team = Self.launchTeam { path.append(team) } }
            .environment(\.vexTheme, VEXTheme.named(themeID))
            .preferredColorScheme(.dark)
            .tint(VEXTheme.named(themeID).accent)
        }
    }
}
