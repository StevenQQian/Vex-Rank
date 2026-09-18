import SwiftUI
import VEXRankKit

@available(iOS 17.0, *)
@main
struct VEXRankApp: App {
    @AppStorage("vexrank-theme") private var themeID: String = VEXTheme.midnight.id
    @State private var path = NavigationPath()
    @State private var eventPath = NavigationPath()
    @State private var statPath = NavigationPath()
    @State private var teamsPath = NavigationPath()
    /// `-tab teams` opens on that tab. Seeded as the State's initial value,
    /// not assigned on appear, for the same reason the profile's season is:
    /// an assignment made as the view settles can be lost.
    @State private var tab = VEXRankApp.launchTab

    /// `-team 31260X` opens straight to a profile. Used for verifying the
    /// profile without tapping, and the hook a URL scheme will reuse.
    private static func launchArgument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private static var launchTeam: String? { launchArgument("-team") }

    private static var launchTab: Int {
        switch launchArgument("-tab") {
        case "events": return 1
        case "stats": return 2
        case "teams": return 3
        default: return launchEvent == nil ? 0 : 1
        }
    }
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

                NavigationStack(path: $teamsPath) {
                    TeamsDirectoryView()
                        .navigationTitle("Teams")
                        .navigationDestination(for: String.self) { TeamProfileView(number: $0) }
                        .navigationDestination(for: EventRef.self) { EventDetailView(event: $0) }
                        .toolbar { themeMenu }
                }
                .tabItem { Label("Teams", systemImage: "person.3") }
                .tag(3)
            }
            .onAppear {
                if let team = Self.launchTeam { path.append(team) }
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
