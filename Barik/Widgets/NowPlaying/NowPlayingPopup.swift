import AVKit
import EventKit
import SwiftUI

/// The now playing popup, laid out like the Now Playing screen of Music on iPhone: the artwork across the popup's
/// width, the full title and artist, the timeline, the playback controls, and AirPlay. The title and artist wrap
/// instead of being cut off, so the popup never shows less of them than the bar; the artwork stays as it is while
/// paused, as the controls already show the state.
struct NowPlayingPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    private let width: CGFloat = 300
    private let padding: CGFloat = 25

    var body: some View {
        if let song = playingManager.nowPlaying {
            VStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 15) {
                    RotateAnimatedCachedImage(
                        url: song.albumArtURL,
                        targetSize: CGSize(width: 500, height: 500)
                    ) { image in
                        image.clipShape(artworkShape)
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
                }
                .opensPlayingApp(song)

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
        } else {
            NothingPlayingView()
                .padding(30)
                .frame(width: width)
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
                .font(.headline)
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
private struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVRoutePickerView, context: Context) -> CGSize? {
        CGSize(width: 24, height: 24)
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
