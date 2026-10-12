import AVKit
import EventKit
import SwiftUI

/// The now playing popup, laid out like the Now Playing screen of Music on iPhone: the artwork across the popup's
/// width, the full title and artist, the timeline, the playback controls, and AirPlay. The title and artist wrap
/// instead of being cut off, so the popup never shows less of them than the bar; the artwork stays as it is while
/// paused, as the controls already show the state.
struct NowPlayingPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared
    @ObservedObject private var configManager = ConfigManager.shared

    /// The client ID of the user's app in the Spotify developer dashboard (`spotify.client-id`), read from
    /// ConfigManager like `CalendarPopup` so an open popup follows edits of the config.
    private var spotifyClientID: String? {
        let clientID = configManager.globalWidgetConfig(for: "default.nowplaying")["spotify"]?
            .dictionaryValue?["client-id"]?.stringValue
        return clientID?.isEmpty == false ? clientID : nil
    }

    private let width: CGFloat = 300
    private let padding = Constants.popupPadding

    var body: some View {
        if let song = playingManager.nowPlaying {
            // A very long title or artist scrolls with the popup (see MenuBarPopupView).
            content(song)
        } else {
            NothingPlayingView()
                .padding(padding)
                .frame(width: width)
        }
    }

    private func content(_ song: NowPlayingSong) -> some View {
        VStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 15) {
                RotateAnimatedCachedImage(
                    url: song.albumArtURL,
                    targetSize: CGSize(width: 500, height: 500)
                ) { image in
                    image.clipShape(artworkShape)
                } placeholder: {
                    ArtworkPlaceholder(shape: artworkShape)
                }
                .frame(width: width - padding * 2, height: width - padding * 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    // Some players, such as Firefox, report an empty artist.
                    if !song.artist.isEmpty {
                        Text(song.artist)
                            .font(.headline)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, likeButtonClientID(for: song) == nil ? 0 : LikeButton.width)
            }
            .opensPlayingApp(song)
            // Beside the title, where Music puts the favorite button. It is laid over the button that opens the app
            // rather than inside it, as a button inside another does not receive its own clicks.
            .overlay(alignment: .bottomTrailing) {
                if let clientID = likeButtonClientID(for: song) {
                    LikeButton(song: song, clientID: clientID)
                }
            }

            PlaybackTimeline(song: song)

            HStack(spacing: 40) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20))
                    .barButton(label: "Previous Track") { playingManager.previousTrack() }
                Image(systemName: song.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 30))
                    .barButton(label: song.state == .paused ? "Play" : "Pause") { playingManager.togglePlayPause() }
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .barButton(label: "Next Track") { playingManager.nextTrack() }
            }

            AirPlayButton()
        }
        .padding(padding)
        .frame(width: width)
        .animation(.easeInOut, value: song.albumArtURL)
    }

    /// The client ID when the song plays in Spotify and the config has one; otherwise the popup shows no like button.
    private func likeButtonClientID(for song: NowPlayingSong) -> String? {
        song.bundleIdentifier == SpotifyAPI.bundleIdentifier ? spotifyClientID : nil
    }
}

/// Shows whether the song is in the Spotify Liked Songs and adds or removes it. Before signing in, it signs in.
private struct LikeButton: View {
    let song: NowPlayingSong
    let clientID: String

    @ObservedObject private var library = SpotifyLibrary.shared

    static let width: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .foregroundStyle(library.state == .liked(true) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy, value: library.state)
            .frame(width: Self.width, height: Self.width)
            .barButton(label: label) { press() }
            .help(Text(label))
            // Never disabled: a disabled button dims while the state loads or a change is sent, which flickered, and
            // shows no help tag (measured), which is how the paused state explains itself. Presses that cannot act
            // are ignored (see `press` and `SpotifyLibrary.toggle`).
            // Read when the popup opens, when the song changes, when it starts or stops playing and after signing in;
            // the request stops when the popup closes.
            .task(id: "\(song.id)\u{1f}\(song.state.rawValue)\u{1f}\(library.state == .signedOut)") {
                await library.refresh(song: song, clientID: clientID)
            }
    }

    private var symbol: String {
        switch library.state {
        case .liked(true): "heart.fill"
        case .failed: "exclamationmark.triangle"
        default: "heart"
        }
    }

    private var label: LocalizedStringKey {
        switch library.state {
        case .signedOut: "Sign In to Spotify"
        case .loading: "Add to Liked Songs"
        case .paused: "Play the Song to See If It Is Liked"
        case .liked(true): "Remove from Liked Songs"
        case .liked(false): "Add to Liked Songs"
        case .failed: "Could Not Read the Liked Songs"
        }
    }

    private func press() {
        // Not tied to the popup: signing in continues in the browser after the popup closes.
        Task {
            switch library.state {
            case .signedOut: await library.signIn(clientID: clientID)
            case .liked: await library.toggle(clientID: clientID)
            case .failed, .paused: await library.refresh(song: song, clientID: clientID)
            case .loading: break
            }
        }
    }
}

/// Shown when playback ends while the popup is open, instead of an empty popup.
private struct NothingPlayingView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 30))
                .accessibilityHidden(true)
            Text("Nothing Playing")
                .font(.popupHeading)
        }
        .foregroundStyle(.secondary)
    }
}

/// The elapsed and remaining time around a progress bar, updated while the song plays.
private struct PlaybackTimeline: View {
    let song: NowPlayingSong

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            // Live streams report no duration or position, or a duration of 0; keep the song and its controls without
            // the timeline.
            if let duration = song.duration, duration > 0, let position = song.position(at: context.date) {
                HStack {
                    Text(timeString(from: position))
                        .font(.caption)
                    ProgressView(value: position, total: duration)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(Color.primary)
                    Text("-" + timeString(from: duration - position))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .monospacedDigit()
                // VoiceOver reads the timeline as one element, instead of two times and a percentage apart.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Playback position"))
                .accessibilityValue(
                    String(
                        localized: "\(timeString(from: position)) of \(timeString(from: duration))",
                        comment: "VoiceOver value of the playback position: the elapsed time of the song's duration."))
            }
        }
    }
}

/// Converts a time interval in seconds to a formatted string (minutes:seconds, or hours:minutes:seconds from an hour).
private func timeString(from seconds: Double) -> String {
    let intSeconds = Int(seconds)
    let hours = intSeconds / 3600
    let minutes = intSeconds / 60 % 60
    let remainingSeconds = intSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

// MARK: - Previews

struct NowPlayingPopup_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingPopup()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}

/// The artwork's corners: concentric with the glass popup's corners, as the HIG asks for nested rounded shapes, with
/// the previous 10pt radius as the minimum.
private var artworkShape: AnyShape {
    AnyShape(ConcentricRectangle(corners: .concentric(minimum: 10), isUniform: true))
}

/// The system AirPlay button, which lists the Mac's audio outputs and AirPlay devices like the Control Center.
/// Devices are detected while the popup shows the button: the list only had this Mac and "Show More…" when detection
/// started with the click, and listed every device when it was already running.
private struct AirPlayButton: NSViewRepresentable {
    func makeCoordinator() -> AVRouteDetector {
        AVRouteDetector()
    }

    func makeNSView(context: Context) -> AVRoutePickerView {
        context.coordinator.isRouteDetectionEnabled = true
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        return picker
    }

    static func dismantleNSView(_ picker: AVRoutePickerView, coordinator: AVRouteDetector) {
        coordinator.isRouteDetectionEnabled = false
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {}

    /// The picker's own size: it draws its icon centered in that size, so a smaller frame moved the icon off center
    /// and a larger one stretched it.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVRoutePickerView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

extension View {
    /// Makes the artwork and title a button that brings the playing app to the front, as clicking them does in the
    /// Control Center. Without a reported app, the view stays as it is.
    @ViewBuilder
    fileprivate func opensPlayingApp(_ song: NowPlayingSong) -> some View {
        if let app = PlayingApp(bundleIdentifier: song.bundleIdentifier) {
            // The button covers the song's title and artist, so VoiceOver reads them as its value.
            barButton(
                label: "Open \(app.name)",
                value: song.artist.isEmpty ? song.title : "\(song.title), \(song.artist)"
            ) { app.open() }
                .help("Open \(app.name)")
        } else {
            self
        }
    }
}

/// The app playing the song, found from its bundle identifier.
private struct PlayingApp {
    let url: URL
    let name: String

    init?(bundleIdentifier: String?) {
        guard let bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        self.url = url
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func open() {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
