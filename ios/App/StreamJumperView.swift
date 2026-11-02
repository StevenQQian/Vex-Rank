import SwiftUI
import WebKit
import VEXRankKit

/// The jumper (VEXRankKit/StreamJumper.swift): an event's livestream pinned
/// above its schedule, and a jump from any played match to the moment it
/// started. Matches are placed by when they actually started, never by the
/// schedule, from one sync point anyone can set for everyone.
@available(iOS 17.0, *)
@Observable
final class JumperModel {
    private(set) var streams: [EventStream] = []
    private(set) var others: [String] = []
    var isOpen = false
    /// What the player should show: a video, where to start, and a token so
    /// the same jump twice still seeks.
    private(set) var current: (videoId: String, seconds: Int, match: String?, token: UUID)?
    /// The video's position, reported by the player every second.
    var position: Double = 0
    var message: String?

    private var eventId = 0
    private var matches: [Int: DivisionMatch] = [:]
    private var divisions: [Int: Int] = [:]
    private var webcast: String?
    private var shared: [EventStream] = []
    private var local = LocalJumper()

    /// The viewer's own unsaved syncs, links and nudges, per event.
    private struct LocalJumper: Codable { var syncs: [String: EventStream.Sync] = [:]; var added: [EventStream] = []; var nudges: [String: Double] = [:] }
    private var defaultsKey: String { "vexrank-jumper-\(eventId)" }

    @MainActor
    func configure(_ detail: EventDetailResponse) async {
        let first = eventId != detail.event.id
        eventId = detail.event.id
        matches = detail.matchesByID
        divisions = detail.divisionByMatch
        webcast = detail.organizer?.webcast
        if first, let data = UserDefaults.standard.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode(LocalJumper.self, from: data) { local = saved }
        rebuild()
        if first { await refresh() }
    }

    @MainActor
    func refresh() async {
        let listed = StreamJumper.streams(webcast: webcast).streams.map(\.videoId)
        if let response = try? await VEXRankAPI.shared.streams(event: eventId, videos: listed) { shared = response.streams }
        rebuild()
    }

    private func rebuild() {
        let merged = StreamJumper.streams(webcast: webcast, added: shared + local.added)
        others = merged.others
        streams = merged.streams.map { stream in
            var copy = stream
            if let saved = shared.first(where: { $0.videoId == stream.videoId }) {
                copy.startTime = saved.startTime; copy.divisionId = saved.divisionId; copy.sync = saved.sync
            }
            if let mine = local.syncs[stream.videoId] { copy.sync = mine }
            return copy
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(local) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    func nudge(for videoId: String) -> Double { local.nudges[videoId] ?? 0 }

    func jump(for matchId: Int) -> MatchJump? {
        guard let match = matches[matchId] else { return nil }
        return StreamJumper.jump(to: match, divisionId: divisions[matchId], streams: streams, matches: matches, nudges: local.nudges)
    }

    func jump(to matchId: Int) {
        guard let target = jump(for: matchId) else { return }
        current = (target.videoId, target.seconds, matches[matchId]?.name, UUID())
        isOpen = true
    }

    func open() {
        if current == nil, let first = streams.first { current = (first.videoId, -1, nil, UUID()) }
        isOpen = true
    }

    func show(_ videoId: String) { current = (videoId, -1, nil, UUID()) }

    /// Moves the stream's placement by `delta` seconds and the video with it.
    func nudge(_ delta: Double) {
        guard let videoId = current?.videoId else { return }
        local.nudges[videoId, default: 0] += delta
        persist()
        current = (videoId, Int(max(0, position + delta)), current?.match, UUID())
    }

    /// Played matches, in the order they were played, for the sync picker.
    var playedMatches: [DivisionMatch] {
        matches.values.filter { $0.started != nil }.sorted { ($0.started ?? "") < ($1.started ?? "") }
    }

    var lastMatchId: Int? {
        guard let name = current?.match else { return nil }
        return matches.values.first { $0.name == name }?.id
    }

    /// "This match starts here": saved for everyone, and kept on this device
    /// so it holds even if the save does not go through.
    @MainActor
    func sync(matchId: Int) async {
        guard let videoId = current?.videoId, position >= 1 else { return }
        let sync = EventStream.Sync(matchId: matchId, seconds: position.rounded())
        local.syncs[videoId] = sync
        local.nudges[videoId] = 0
        persist(); rebuild()
        if let response = try? await VEXRankAPI.shared.postStream(["event": eventId, "videoId": videoId, "sync": ["matchId": matchId, "seconds": sync.seconds]]) {
            shared = response.streams
            local.syncs[videoId] = nil
            persist(); rebuild()
            message = "Synced for everyone."
        } else {
            message = "Synced on this device (could not save it for others)."
        }
    }

    @MainActor
    func add(_ link: String) async {
        guard let videoId = StreamJumper.youtubeID(link) else {
            message = "Paste a YouTube video or live link - a channel page cannot be jumped in."
            return
        }
        if let response = try? await VEXRankAPI.shared.postStream(["event": eventId, "url": link]) {
            shared = response.streams
        } else if !local.added.contains(where: { $0.videoId == videoId }) {
            local.added.append(EventStream(videoId: videoId, url: link, source: "viewer"))
            persist()
        }
        rebuild()
        show(videoId)
        message = "Stream added."
    }
}

/// The player and its controls, pinned above a match list.
@available(iOS 17.0, *)
struct JumperPanel: View {
    @Bindable var jumper: JumperModel
    @Environment(\.vexTheme) private var theme
    @State private var syncMatch: Int?
    @State private var addingLink = false
    @State private var link = ""

    private static let nudges: [Double] = [-60, -30, -10, -5, 5, 10, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVESTREAM").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if let current = jumper.current, let match = current.match {
                    Text("· \(match) at \(StreamJumper.videoTime(Double(max(0, current.seconds))))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { addingLink = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a stream link")
                Button { jumper.isOpen = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close livestream")
            }
            .font(.footnote.weight(.semibold))
            .tint(theme.accent)

            if let current = jumper.current {
                // Full width at 16:9: the panel keeps its natural height (below)
                // rather than giving way to the list it sits above.
                Color.black
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay { YouTubePlayer(videoId: current.videoId, seconds: current.seconds, token: current.token) { jumper.position = $0 } }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if jumper.streams.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(jumper.streams.enumerated()), id: \.element.id) { index, stream in
                                Button("Stream \(index + 1)") { jumper.show(stream.videoId) }
                                    .buttonStyle(.bordered)
                                    .tint(stream.videoId == current.videoId ? theme.accent : .secondary)
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                }

                HStack(spacing: 4) {
                    ForEach(Self.nudges, id: \.self) { delta in
                        Button {
                            jumper.nudge(delta)
                        } label: {
                            Text("\(delta < 0 ? "−" : "+")\(abs(delta) >= 60 ? "\(Int(abs(delta) / 60))m" : "\(Int(abs(delta)))s")")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let stream = jumper.streams.first { $0.videoId == current.videoId }
                Text(stream?.isTimed == true
                     ? "Matches are placed by when they actually started. If a jump lands off, nudge it, or re-sync below."
                     : "Not synced yet: play to the start of any match, pick it below and tap Starts at. Every match then gets a jump, for everyone.")
                    .font(.caption2).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(jumper.playedMatches.reversed()) { match in
                            Button(match.name ?? "Match") { syncMatch = match.id }
                        }
                    } label: {
                        Text(jumper.playedMatches.first { $0.id == (syncMatch ?? jumper.lastMatchId) }?.name ?? "Match on screen…")
                            .font(.caption).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Button("Starts at \(StreamJumper.videoTime(jumper.position))") {
                        guard let id = syncMatch ?? jumper.lastMatchId else { return }
                        Task { await jumper.sync(matchId: id) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
                    .disabled((syncMatch ?? jumper.lastMatchId) == nil || jumper.position < 1)
                }
            } else {
                Text("No livestream is listed for this event yet. Tap + to add its YouTube link.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let message = jumper.message {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider().overlay(Color.hairline) }
        .alert("Add a stream link", isPresented: $addingLink) {
            TextField("YouTube link", text: $link)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") { let value = link; link = ""; Task { await jumper.add(value) } }
            Button("Cancel", role: .cancel) { link = "" }
        } message: {
            Text("A YouTube video or live link for this event.")
        }
    }
}

/// ▶ beside a match: jumps the livestream to it, when it can be placed.
@available(iOS 17.0, *)
struct JumpButton: View {
    let jumper: JumperModel
    let matchId: Int
    let name: String
    @Environment(\.vexTheme) private var theme

    var body: some View {
        if let target = jumper.jump(for: matchId) {
            Button { jumper.jump(to: matchId) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .accessibilityLabel("Watch \(name) on the livestream, at \(StreamJumper.videoTime(Double(target.seconds)))")
        }
    }
}

/// "Watch livestream" / "Add livestream", for a section header or toolbar.
@available(iOS 17.0, *)
struct WatchButton: View {
    let jumper: JumperModel
    @Environment(\.vexTheme) private var theme

    var body: some View {
        Button { jumper.open() } label: {
            Label(jumper.streams.isEmpty ? "Add livestream" : "Watch livestream", systemImage: "play.rectangle")
                .font(.caption.weight(.semibold))
        }
        .tint(theme.accent)
    }
}

/// YouTube's IFrame player in a web view. A new token with the same video
/// seeks; a new video loads; seconds of -1 just opens it. The position comes
/// back every second for the sync button.
@available(iOS 17.0, *)
struct YouTubePlayer: UIViewRepresentable {
    let videoId: String
    let seconds: Int
    let token: UUID
    let onTime: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTime: onTime) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "jumper")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        context.coordinator.view = view
        // An https origin, which the embedded player needs to accept the page.
        view.loadHTMLString(Self.page(videoId: videoId, start: max(0, seconds), autoplay: seconds >= 0), baseURL: URL(string: "https://vex-rank.com"))
        context.coordinator.shown = (videoId, token)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onTime = onTime
        guard context.coordinator.shown?.token != token else { return }
        let sameVideo = context.coordinator.shown?.videoId == videoId
        context.coordinator.shown = (videoId, token)
        let script = sameVideo
            ? (seconds >= 0 ? "jump(\(seconds))" : "")
            : (seconds >= 0 ? "load('\(videoId)', \(seconds))" : "cue('\(videoId)')")
        if !script.isEmpty { view.evaluateJavaScript(script) }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "jumper")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onTime: (Double) -> Void
        weak var view: WKWebView?
        var shown: (videoId: String, token: UUID)?
        init(onTime: @escaping (Double) -> Void) { self.onTime = onTime }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let time = message.body as? Double { onTime(time) } else if let time = message.body as? Int { onTime(Double(time)) }
        }
    }

    private static func page(videoId: String, start: Int, autoplay: Bool) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}#player{width:100%;height:100%}</style></head>
        <body><div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player, pending = null;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', { videoId: '\(videoId)', playerVars: { start: \(start), autoplay: \(autoplay ? 1 : 0), playsinline: 1, rel: 0, modestbranding: 1 },
            events: { onReady: function () { if (pending) { pending(); pending = null; } } } });
        }
        function whenReady(work) { if (player && player.seekTo) work(); else pending = work; }
        function jump(s) { whenReady(function () { player.seekTo(s, true); player.playVideo(); }); }
        function load(id, s) { whenReady(function () { player.loadVideoById({ videoId: id, startSeconds: s }); }); }
        function cue(id) { whenReady(function () { player.cueVideoById({ videoId: id }); }); }
        setInterval(function () { if (player && player.getCurrentTime) window.webkit.messageHandlers.jumper.postMessage(player.getCurrentTime()); }, 1000);
        </script></body></html>
        """
    }
}
