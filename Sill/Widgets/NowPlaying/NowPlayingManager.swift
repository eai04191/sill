import AppKit
import Combine
import Foundation
import os

// MARK: - Playback State

/// Represents the current playback state.
enum PlaybackState: String {
    case playing, paused
}

// MARK: - Now Playing Song Model

/// A model representing the currently playing song.
struct NowPlayingSong: Equatable, Identifiable {
    var id: String { title + artist }
    let state: PlaybackState
    let title: String
    let artist: String
    let albumArtURL: URL?
    let duration: Double?  // Duration in seconds
    /// The elapsed time in seconds at `elapsedTimeMeasuredAt`. The model holds this measurement rather than the
    /// position, so that it does not change while the song plays and the bar is not re-rendered for the position.
    let elapsedTime: Double?
    let elapsedTimeMeasuredAt: Date?
    let playbackRate: Double
    /// The app playing the song, as reported to Now Playing.
    let bundleIdentifier: String?

    /// The position in seconds at `date`, estimated from the elapsed time while playing.
    func position(at date: Date) -> Double? {
        guard var position = elapsedTime else { return nil }
        if state == .playing, let elapsedTimeMeasuredAt {
            position += date.timeIntervalSince(elapsedTimeMeasuredAt) * playbackRate
        }
        if let duration {
            position = min(max(position, 0), duration)
        }
        return position
    }
}

// MARK: - media-control Payload

/// The now playing information reported by `media-control stream`.
///
/// macOS 15.4 restricted the MediaRemote framework, so the widget reads the system-wide
/// now playing session through media-control (https://github.com/ungive/media-control).
/// Unlike AppleScript, this covers every player that reports to Now Playing,
/// including browsers such as Firefox.
struct MediaControlPayload: Decodable, Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let playing: Bool?
    let playbackRate: Double?
    let bundleIdentifier: String?
    // Read with `--micros`: the default `timestamp` is an ISO 8601 date with whole seconds, which made the estimated
    // position drift by up to a second.
    let elapsedTimeMicros: Double?
    let durationMicros: Double?
    let timestampEpochMicros: Double?

    var elapsedTime: Double? { elapsedTimeMicros.map { $0 / 1_000_000 } }
    var duration: Double? { durationMicros.map { $0 / 1_000_000 } }

    /// The moment `elapsedTime` was measured.
    var timestampDate: Date? {
        timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) }
    }

    /// Identifies the track, so the artwork is fetched again only when it changes.
    /// media-control's `contentItemIdentifier` is not used because it changes on every play/pause of the same track.
    var trackKey: String {
        [bundleIdentifier, title, artist, album].map { $0 ?? "" }.joined(separator: "\u{1f}")
    }

    /// Builds the song model.
    func song(artworkURL: URL?) -> NowPlayingSong? {
        guard let title, !title.isEmpty else { return nil }
        return NowPlayingSong(
            state: playing == true ? .playing : .paused,
            title: title,
            artist: artist ?? "",
            albumArtURL: artworkURL,
            duration: duration,
            elapsedTime: elapsedTime,
            elapsedTimeMeasuredAt: timestampDate,
            playbackRate: playbackRate ?? 1,
            bundleIdentifier: bundleIdentifier)
    }
}

// MARK: - media-control Process

/// Runs media-control and exposes its now playing stream and playback commands.
final class MediaControl {
    /// Homebrew installs media-control in one of these locations.
    /// Looked up on every use, so that installing media-control while Sill runs takes effect.
    static var executableURL: URL? {
        ["/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Seconds before starting media-control again after it exits or fails to start.
    private static let restartDelay: TimeInterval = 5
    /// Seconds between looks for media-control while it is not installed.
    private static let installCheckInterval: TimeInterval = 30
    /// Seconds after which `get` is stopped, so a hung media-control does not hold the artwork fetch.
    private static let getTimeout: TimeInterval = 5
    /// The stream prints one line per update of a few hundred bytes, so a longer line is not an update, and is not
    /// kept in memory without a limit.
    private static let lineLimit = 1_000_000

    private let onPayload: (MediaControlPayload?) -> Void
    private var process: Process?
    private var buffer = Data()
    private var stopped = false
    private var reportedMissing = false

    /// - Parameter onPayload: Called on the main queue with each update; `nil` means nothing is playing.
    init(onPayload: @escaping (MediaControlPayload?) -> Void) {
        self.onPayload = onPayload
    }

    /// Starts streaming, restarting media-control if it exits unexpectedly or fails to start, and waiting for it to be
    /// installed if it is missing.
    func start() {
        stopped = false
        launch()
    }

    private func launch() {
        guard let executableURL = Self.executableURL else {
            if !reportedMissing {
                Logger.nowPlaying.error("media-control was not found; install it with `brew install media-control`")
                reportedMissing = true
            }
            relaunch(after: Self.installCheckInterval)
            return
        }
        reportedMissing = false
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["stream", "--no-diff", "--no-artwork", "--micros"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            // At the end of the output the handler is called again and again with no data until it is removed.
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                // A media-control replaced by `restart()` may still print, which must not mix with the new stream.
                guard let self, let process, self.process === process else { return }
                self.receive(data)
            }
        }
        process.terminationHandler = { [weak self] exited in
            Logger.nowPlaying.notice(
                "media-control, pid \(exited.processIdentifier, privacy: .public), exited: reason \(exited.terminationReason.rawValue, privacy: .public), status \(exited.terminationStatus, privacy: .public)"
            )
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                // A media-control replaced by `restart()` or stopped by `stop()` is not started again.
                guard let self, self.process === exited else { return }
                self.relaunch(after: Self.restartDelay)
            }
        }
        do {
            try process.run()
            Logger.nowPlaying.notice("Started media-control, pid \(process.processIdentifier, privacy: .public)")
            self.process = process
        } catch {
            Logger.nowPlaying.error("Could not start media-control: \(String(describing: error), privacy: .public)")
            pipe.fileHandleForReading.readabilityHandler = nil
            relaunch(after: Self.restartDelay)
        }
    }

    private func relaunch(after delay: TimeInterval) {
        process = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.buffer.removeAll()
            self.launch()
        }
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    /// Starts media-control again now, as its stream can stop reporting after the Mac sleeps without exiting, which
    /// left the song from before the sleep shown. Waiting for a restart is left to the one already scheduled.
    func restart() {
        guard !stopped, let process else { return }
        Logger.nowPlaying.notice("Restarting media-control")
        self.process = nil
        ProcessStopper.stop(process)
        buffer.removeAll()
        launch()
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = try? JSONDecoder().decode(StreamMessage.self, from: line) else { continue }
            onPayload(message.payload.title == nil ? nil : message.payload)
        }
        if buffer.count > Self.lineLimit {
            Logger.nowPlaying.error("media-control printed more than \(Self.lineLimit, privacy: .public) bytes without a line break; restarting it")
            let overflowing = process
            // Clears the process first, so its remaining output and its exit are ignored.
            relaunch(after: Self.restartDelay)
            if let overflowing { ProcessStopper.stop(overflowing) }
        }
    }

    private struct StreamMessage: Decodable {
        let payload: MediaControlPayload
    }

    /// Fetches the current artwork, which the stream omits to avoid sending it with every update, with the key of the
    /// track `get` reported it for, as the track can change between a stream update and `get`.
    static func fetchArtwork() -> (trackKey: String, artwork: (data: Data, fileExtension: String)?)? {
        guard let executableURL else { return nil }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["get"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Read as it arrives rather than to the end of the output, which a process left running by media-control
        // could hold open after media-control is stopped (see `OutputReader`).
        let reader = OutputReader(pipe.fileHandleForReading)
        do {
            try process.run()
        } catch {
            _ = reader.finish()
            return nil
        }
        ProcessStopper.stop(process, after: getTimeout)
        process.waitUntilExit()
        let output = reader.finish()
        guard let payload = try? JSONDecoder().decode(MediaControlPayload.self, from: output),
            let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any]
        else {
            return nil
        }
        guard let base64 = json["artworkData"] as? String, let data = Data(base64Encoded: base64) else {
            return (payload.trackKey, nil)
        }
        let fileExtension = (json["artworkMimeType"] as? String) == "image/png" ? "png" : "jpg"
        return (payload.trackKey, (data, fileExtension))
    }

    static func run(_ command: String) {
        guard let executableURL else { return }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [command]
        try? process.run()
    }
}

// MARK: - Now Playing Manager

/// An observable manager that follows the system-wide now playing session.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlayingSong?

    private var mediaControl: MediaControl?
    private var payload: MediaControlPayload?
    private var artworkURL: URL?
    private var artworkTrackKey: String?
    /// The track artwork was last fetched for, and how many times.
    private var fetchTrackKey: String?
    private var fetchCount = 0
    /// Set while get runs, so stream updates do not start more fetches at once.
    private var isFetchingArtwork = false
    /// A track is fetched at most this many times, as some players, such as browsers, may never report an artwork.
    private static let maxArtworkFetches = 3
    private var terminateObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// Album art is written to this directory so the existing URL-based image views can load it.
    private let artworkDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sill-now-playing", isDirectory: true)

    private init() {
        try? FileManager.default.removeItem(at: artworkDirectory)
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)

        mediaControl = MediaControl { [weak self] payload in
            self?.update(payload)
        }
        mediaControl?.start()

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.mediaControl?.stop()
        }

        // The stream can stop reporting after sleep without exiting, so it is started again on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.mediaControl?.restart()
        }
    }

    private func update(_ payload: MediaControlPayload?) {
        self.payload = payload
        guard let payload else {
            setArtwork(nil, for: nil)
            fetchTrackKey = nil
            publish()
            return
        }
        fetchArtworkIfNeeded(for: payload.trackKey)
        publish()
    }

    /// The artwork sometimes arrives after the title, so a track without one is fetched again on later updates, up to
    /// `maxArtworkFetches` times.
    private func fetchArtworkIfNeeded(for trackKey: String) {
        if trackKey != fetchTrackKey {
            fetchTrackKey = trackKey
            fetchCount = 0
        }
        let hasArtwork = artworkTrackKey == trackKey && artworkURL != nil
        guard !hasArtwork, !isFetchingArtwork, fetchCount < Self.maxArtworkFetches else { return }
        isFetchingArtwork = true
        fetchCount += 1
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fetched = MediaControl.fetchArtwork()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingArtwork = false
                // The artwork is stored only for the track get reported it for, which is still the current one.
                if let fetched, fetched.trackKey == trackKey, self.payload?.trackKey == trackKey {
                    self.setArtwork(fetched.artwork, for: trackKey)
                    self.publish()
                }
                // An update for another track during the fetch did not start one for that track.
                if let current = self.payload?.trackKey, current != trackKey {
                    self.fetchArtworkIfNeeded(for: current)
                }
            }
        }
    }

    /// Writes each artwork to a new file, because the image cache is keyed by URL.
    private func setArtwork(_ artwork: (data: Data, fileExtension: String)?, for trackKey: String?) {
        if let artworkURL {
            try? FileManager.default.removeItem(at: artworkURL)
        }
        artworkURL = nil
        artworkTrackKey = trackKey
        guard let artwork else { return }
        let url = artworkDirectory.appendingPathComponent("\(UUID().uuidString).\(artwork.fileExtension)")
        if (try? artwork.data.write(to: url)) != nil {
            artworkURL = url
        }
    }

    private func publish() {
        // A new track shows no artwork until its own is fetched, rather than the previous track's.
        let song = payload?.song(artworkURL: artworkTrackKey == payload?.trackKey ? artworkURL : nil)
        if song != nowPlaying {
            nowPlaying = song
        }
    }

    /// Skips to the previous track.
    func previousTrack() {
        MediaControl.run("previous-track")
    }

    /// Toggles between play and pause.
    func togglePlayPause() {
        MediaControl.run("toggle-play-pause")
    }

    /// Skips to the next track.
    func nextTrack() {
        MediaControl.run("next-track")
    }
}
