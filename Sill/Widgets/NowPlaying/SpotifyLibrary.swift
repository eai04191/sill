import Foundation
import os

/// Whether the song playing in Spotify is in the user's Liked Songs, read and changed while the now playing popup
/// is open (see `NowPlayingPopup`). Nothing is requested while the popup is closed.
///
/// Spotify sends no notice when the song is liked elsewhere, such as in the app, so the state is read again each time
/// the popup opens, the track changes and the song starts or stops playing.
@MainActor
final class SpotifyLibrary: ObservableObject {
    static let shared = SpotifyLibrary()

    enum State: Equatable {
        case signedOut
        case loading
        case liked(Bool)
        /// The song is paused and Spotify reports nothing playing, which it does once playback has been paused for a
        /// while (measured: 204 with Spotify paused); the state is read when the song plays again, or when the button
        /// is pressed.
        case paused
        /// The track was not found or Spotify did not answer; pressing the button reads it again.
        case failed
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var isUpdating = false

    /// The track the state is for.
    private var trackURI: String?
    /// The song the state is for, so reading the same song again keeps showing its state instead of loading.
    private var stateSongID: String?
    /// Counts the reads and changes, so a read applies its result only when no newer read or change started since.
    /// A read started from the button is not cancelled with the popup's task and may finish after a newer one.
    private var generation = 0

    /// Retries while Spotify still reports the previous track after a change (see `SpotifyAPI.playingTrackURI`).
    private static let matchAttempts = 4
    private static let matchRetryDelay: Duration = .seconds(1)

    private var account: SpotifyAccount { .shared }

    /// Reads the state of the song. Called when the popup appears, when the song changes and when it starts or stops
    /// playing, and cancelled with the popup's task.
    func refresh(song: NowPlayingSong, clientID: String) async {
        generation += 1
        let generation = generation
        // A change being sent shows its state already; a read now could answer from before the change.
        if isUpdating, stateSongID == song.id { return }
        guard account.isSignedIn else {
            trackURI = nil
            state = .signedOut
            return
        }
        if stateSongID != song.id {
            trackURI = nil
            stateSongID = song.id
            state = .loading
        }
        do {
            let uri = try await playingTrackURI(song: song, clientID: clientID)
            guard generation == self.generation else { return }
            guard let uri else {
                trackURI = nil
                if song.state == .paused {
                    state = .paused
                } else {
                    Logger.nowPlaying.notice("Spotify did not report the song shown as playing")
                    state = .failed
                }
                return
            }
            let (data, response) = try await account.send(
                URLRequest(url: SpotifyAPI.libraryContainsURL(for: uri)), clientID: clientID)
            guard generation == self.generation else { return }
            guard response.statusCode == 200, let liked = SpotifyAPI.isInLibrary(data) else {
                throw SpotifyError.http(response.statusCode)
            }
            trackURI = uri
            state = .liked(liked)
        } catch {
            guard generation == self.generation else { return }
            handle(error, while: "reading the Liked Songs")
        }
    }

    /// Adds the track to the Liked Songs or removes it. The new state shows at once rather than after Spotify's
    /// answer, a few hundred milliseconds later, and goes back if Spotify does not accept the change.
    func toggle(clientID: String) async {
        guard case .liked(let liked) = state, let trackURI, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        generation += 1
        state = .liked(!liked)
        var request = URLRequest(url: SpotifyAPI.libraryURL(for: trackURI))
        request.httpMethod = liked ? "DELETE" : "PUT"
        do {
            let (_, response) = try await account.send(request, clientID: clientID)
            guard (200..<300).contains(response.statusCode) else { throw SpotifyError.http(response.statusCode) }
        } catch {
            // Unless the track changed while the request was sent.
            if self.trackURI == trackURI, state == .liked(!liked) {
                state = .liked(liked)
            }
            handle(
                error, while: liked ? "removing the song from the Liked Songs" : "adding the song to the Liked Songs",
                keepsState: true)
        }
    }

    /// Signs in and leaves reading the state to the popup, which reads it when the state leaves `signedOut` if it is
    /// still open; the browser usually closes it.
    func signIn(clientID: String) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await account.signIn(clientID: clientID)
            stateSongID = nil
            state = .loading
        } catch {
            handle(error, while: "signing in")
        }
    }

    private func playingTrackURI(song: NowPlayingSong, clientID: String) async throws -> String? {
        for attempt in 1...Self.matchAttempts {
            let (data, response) = try await account.send(
                URLRequest(url: SpotifyAPI.currentlyPlayingURL), clientID: clientID)
            guard response.statusCode == 200 || response.statusCode == 204 else {
                throw SpotifyError.http(response.statusCode)
            }
            if let uri = SpotifyAPI.playingTrackURI(in: data, songDuration: song.duration) {
                return uri
            }
            // Nothing playing while paused stays so; retrying is for a track change while playing.
            if response.statusCode == 204, song.state == .paused {
                return nil
            }
            if attempt < Self.matchAttempts {
                try await Task.sleep(for: Self.matchRetryDelay)
            }
        }
        return nil
    }

    /// Shows a failure, or the sign-in when Spotify no longer accepts the token. A failed change keeps showing the
    /// state Spotify last reported (`keepsState`).
    private func handle(_ error: Error, while action: String, keepsState: Bool = false) {
        switch error {
        case is CancellationError:
            return
        case let error as URLError where error.code == .cancelled:
            return
        case SpotifyError.signedOut:
            state = .signedOut
        default:
            // 403 means the account is not in the app's users in the developer dashboard (Development Mode).
            Logger.nowPlaying.error("Spotify failed while \(action, privacy: .public): \(String(describing: error), privacy: .public)")
            if keepsState { return }
            trackURI = nil
            state = account.isSignedIn ? .failed : .signedOut
        }
    }
}
