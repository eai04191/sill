import AVKit
import EventKit
import SwiftUI

struct NowPlayingPopup: View {
    @ObservedObject var configProvider: ConfigProvider
    @State private var selectedVariant: MenuBarPopupVariant = .horizontal

    var body: some View {
        // The colors of every variant adapt to the appearance; popups are always dark (see MenuBarPopupView).
        variantView
    }

    private var variantView: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.nowplaying.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            vertical: { NowPlayingVerticalPopup() },
            horizontal: { NowPlayingHorizontalPopup() }
        )
        .onAppear(perform: loadVariant)
        .onReceive(configProvider.$config, perform: updateVariant)
    }
    
    /// Loads the initial view variant from configuration.
    private func loadVariant() {
        if let variantString = configProvider.config["popup"]?
            .dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString), variant != .box {
            selectedVariant = variant
        } else {
            // This popup has no box variant, so falling back to .box rendered an empty popup.
            selectedVariant = .horizontal
        }
    }
    
    /// Updates the view variant when configuration changes. There is no box variant to switch to.
    private func updateVariant(newConfig: ConfigData) {
        if let variantString = newConfig["popup"]?.dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString), variant != .box {
            selectedVariant = variant
        }
    }
}

/// A vertical layout for the now playing popup.
private struct NowPlayingVerticalPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    var body: some View {
        if let song = playingManager.nowPlaying {
            VStack(spacing: 15) {
                VStack(spacing: 15) {
                    RotateAnimatedCachedImage(
                        url: song.albumArtURL,
                        targetSize: CGSize(width: 200, height: 200)
                    ) { image in
                        image.clipShape(artworkShape)
                    }
                    .frame(width: 200, height: 200)
                    .scaleEffect(song.state == .paused ? 0.9 : 1)
                    .overlay(
                        song.state == .paused ?
                        Color.black.opacity(0.3)
                            .clipShape(artworkShape)
                        : nil
                    )
                    .animation(.smooth(duration: 0.5, extraBounce: 0.4), value: song.state == .paused)

                    VStack(alignment: .center) {
                        Text(song.title)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 15))
                            .fontWeight(.medium)
                        // Some players, such as Firefox, report an empty artist.
                        if !song.artist.isEmpty {
                            Text(song.artist)
                                .opacity(0.6)
                                .font(.system(size: 15))
                                .fontWeight(.light)
                        }
                    }
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
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 30)
            .frame(width: 300)
            .overlay(alignment: .topTrailing) {
                AirPlayButton().padding(12)
            }
            .animation(.easeInOut, value: song.albumArtURL)
        } else {
            NothingPlayingView()
                .padding(30)
                .frame(width: 300)
        }
    }
}

/// A horizontal layout for the now playing popup.
struct NowPlayingHorizontalPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    var body: some View {
        if let song = playingManager.nowPlaying {
            VStack(spacing: 15) {
                HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 15) {
                    RotateAnimatedCachedImage(
                        url: song.albumArtURL,
                        targetSize: CGSize(width: 200, height: 200)
                    ) { image in
                        image.clipShape(artworkShape)
                    }
                    .frame(width: 60, height: 60)
                    .scaleEffect(song.state == .paused ? 0.9 : 1)
                    .overlay(
                        song.state == .paused ?
                        Color.black.opacity(0.3)
                            .clipShape(artworkShape)
                        : nil
                    )
                    .animation(.smooth(duration: 0.5, extraBounce: 0.4), value: song.state == .paused)

                    // The popup has a fixed height, so the text is limited to the artwork's height of three lines
                    // to keep the timeline and controls inside it.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title)
                            .font(.headline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        if !song.artist.isEmpty {
                            Text(song.artist)
                                .opacity(0.6)
                                .font(.headline)
                                .fontWeight(.light)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opensPlayingApp(song)
                AirPlayButton()
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
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
            .frame(width: 300, height: 180)
            .animation(.easeInOut, value: song.albumArtURL)
        } else {
            NothingPlayingView()
                .frame(width: 300, height: 180)
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
        Group {
            NowPlayingVerticalPopup()
                .background(Color.black)
                .frame(height: 600)
                .previewDisplayName("Vertical")
            
            NowPlayingHorizontalPopup()
                .background(Color.black)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Horizontal")
        }
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
