import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
@main
struct VEXRankApp: App {
    @AppStorage("vexrank-theme") private var themeID: String = VEXTheme.midnight.id
    @State private var path = NavigationPath()
    @State private var eventPath = NavigationPath()
    @State private var statPath = NavigationPath()
    @State private var tab = 0

    /// `-team 31260X` opens straight to a profile. Used for verifying the
    /// profile without tapping, and the hook a URL scheme will reuse.
    private static func launchArgument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private static var launchTeam: String? { launchArgument("-team") }
    private static var launchEvent: String? { launchArgument("-event") }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                NavigationStack(path: $path) {
                    RankingsListView()
                        .navigationTitle("World ranking")
                        .navigationDestination(for: String.self) { TeamProfileView(number: $0) }
                        .navigationDestination(for: EventRef.self) { EventDetailView(event: $0) }
                        .toolbar { themeMenu }
                }
                .tabItem { Label("Rankings", systemImage: "trophy") }
                .tag(0)

                NavigationStack(path: $eventPath) {
                    EventsListView(openEventID: Self.launchEvent, path: $eventPath)
                        .navigationTitle("Events")
                        .navigationDestination(for: EventRef.self) { EventDetailView(event: $0) }
                        // Reached by tapping a team in a standings or match row.
                        .navigationDestination(for: String.self) { TeamProfileView(number: $0) }
                        .toolbar { themeMenu }
                }
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(1)

                NavigationStack(path: $statPath) {
                    StatLeadersView()
                        .navigationTitle("Stat leaders")
                        .navigationDestination(for: String.self) { TeamProfileView(number: $0) }
                        .navigationDestination(for: EventRef.self) { EventDetailView(event: $0) }
                        .toolbar { themeMenu }
                }
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(2)
            }
            .onAppear {
                if let team = Self.launchTeam { path.append(team) }
                if Self.launchEvent != nil { tab = 1 }
            }
            .environment(\.vexTheme, VEXTheme.named(themeID))
            .preferredColorScheme(.dark)
            .tint(VEXTheme.named(themeID).accent)
        }
    }

    private var themeMenu: some ToolbarContent {
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
