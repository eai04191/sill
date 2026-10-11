import SwiftUI

// MARK: - Now Playing Widget

struct NowPlayingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject var playingManager = NowPlayingManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var widgetFrame: CGRect = .zero
    @State private var animatedWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if let song = playingManager.nowPlaying {
                // Hidden view for measuring the intrinsic width.
                MeasurableNowPlayingContent(song: song) { measuredWidth in
                    if animatedWidth == 0 {
                        animatedWidth = measuredWidth
                    } else if animatedWidth != measuredWidth {
                        // With Reduce Motion the widget takes its new width at once instead of stretching to it.
                        withAnimation(reduceMotion ? nil : .smooth) {
                            animatedWidth = measuredWidth
                        }
                    }
                }
                // Measured like the visible content, which is in a system glass button (see `barWidgetButton`).
                .environment(\.widgetGlassIsButton, true)
                .hidden()

                // Visible content with fixed animated width.
                VisibleNowPlayingContent(song: song, width: animatedWidth)
                    .barWidgetButton(label: "Now Playing", value: song.artist.isEmpty ? song.title : "\(song.title), \(song.artist)") {
                        MenuBarPopup.show(rect: widgetFrame, id: "nowplaying") {
                            NowPlayingPopup()
                        }
                    }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        widgetFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
    }
}

// MARK: - Now Playing Content

/// A view that composes the album art and song text into a capsule-shaped content view.
struct NowPlayingContent: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    /// A system glass button draws the widget's glass itself (see `barWidgetButton`).
    @Environment(\.widgetGlassIsButton) private var usesSystemGlassButton
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    
    /// A system glass button adds its own margin around the content (see `GlassButtonInset`).
    private var buttonInset: CGSize {
        usesSystemGlassButton ? GlassButtonInset.regular : .zero
    }

    var body: some View {
        // Sized to the bar like the other widgets; it used to lose its background below 38 points.
        HStack(spacing: 8) {
            AlbumArtView(song: song)
            SongTextView(song: song)
        }
        // Below the button's margin the padding is negative, which takes the rest out of the margin.
        .padding(.horizontal, (foregroundHeight < 45 ? 8 : 12) - buttonInset.width)
        .frame(height: barWidgetHeight(forBarHeight: foregroundHeight) - buttonInset.height * 2)
        // The glass is the system glass button around the widget (see `barWidgetButton`).
        // On glass, use the system primary color like the other widgets (see ExperimentalConfigurationModifier).
        .foregroundStyle(Color.primary)
    }
}

// MARK: - Measurable Now Playing Content

/// A wrapper view that measures the intrinsic width of the now playing content.
struct MeasurableNowPlayingContent: View {
    let song: NowPlayingSong
    let onSizeChange: (CGFloat) -> Void

    var body: some View {
        NowPlayingContent(song: song)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            onSizeChange(geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            onSizeChange(newWidth)
                        }
                }
            )
    }
}

// MARK: - Visible Now Playing Content

/// A view that displays now playing content with a fixed, animated width and transition.
struct VisibleNowPlayingContent: View {
    let song: NowPlayingSong
    let width: CGFloat
    /// A system glass button wraps this frame in its glass, so it keeps the widget's own height there.
    @Environment(\.widgetGlassIsButton) private var usesSystemGlassButton

    var body: some View {
        NowPlayingContent(song: song)
            .frame(width: width, height: usesSystemGlassButton ? nil : 38)
            .animation(.smooth(duration: 0.1), value: song)
            .blurReplaceTransition()
    }
}

// MARK: - Album Art View

/// A view that displays the album art with a fade animation and a pause indicator if needed.
struct AlbumArtView: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 20 points, or smaller on a bar too low for it inside the widget.
    private var size: CGFloat {
        min(20, barWidgetHeight(forBarHeight: configManager.config.experimental.foreground.resolveHeight()) - 4)
    }

    var body: some View {
        ZStack {
            FadeAnimatedCachedImage(
                url: song.albumArtURL,
                targetSize: CGSize(width: size, height: size)
            ) { image in
                image
            } placeholder: {
                ArtworkPlaceholder(shape: RoundedRectangle(cornerRadius: 4))
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // Reduce Motion asks to avoid scaling; the dimmed artwork and the pause symbol still show the state.
            .scaleEffect(song.state == .paused && !reduceMotion ? 0.9 : 1)
            .brightness(song.state == .paused ? -0.3 : 0)

            if song.state == .paused {
                Image(systemName: "pause.fill")
                    .foregroundColor(.icon)
                    .blurReplaceTransition()
            }
        }
        .animation(.smooth(duration: 0.1), value: song.state == .paused)
    }
}

// MARK: - Artwork Placeholder

/// Shown in place of the artwork when a song has none or it could not be loaded, like the system's Now Playing: the
/// artwork's shape with a subtle fill and a music note, rather than an empty space.
struct ArtworkPlaceholder<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.quaternary)
            .overlay {
                GeometryReader { geometry in
                    Image(systemName: "music.note")
                        .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.4))
                        .foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Song Text View

/// A view that displays the song title and artist.
struct SongTextView: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {

        VStack(alignment: .leading, spacing: -1) {
            if foregroundHeight >= 30 {
                // Long titles are truncated so the widget fits the space next to centered widgets.
                Text(song.title)
                    .font(.system(size: 11))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.trailing, 2)
                // Some players, such as Firefox, report an empty artist.
                if !song.artist.isEmpty {
                    Text(song.artist)
                        .opacity(0.8)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .padding(.trailing, 2)
                }
            } else {
                Text(song.artist.isEmpty ? song.title : song.artist + " — " + song.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
        }
        // Disable animations for text changes.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

// MARK: - Preview

struct NowPlayingWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            NowPlayingWidget()
        }
        .frame(width: 500, height: 100)
    }
}
