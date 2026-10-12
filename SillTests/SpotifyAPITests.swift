import Foundation
import Testing

@testable import Sill

/// Reading the Spotify Web API's responses, from the shapes returned on 2026-10-12 with fields not read left out.
struct SpotifyAPITests {
    /// The example of RFC 7636, appendix B.
    @Test func codeChallengeMatchesRFC7636() {
        #expect(
            SpotifyAPI.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func codeVerifierIsURLSafeAndLongEnough() {
        let verifier = SpotifyAPI.makeCodeVerifier()
        #expect((43...128).contains(verifier.count))
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    private static func currentlyPlaying(type: String, durationMs: Int?) -> Data {
        let item = durationMs.map { #"{"uri": "spotify:track:53IKYcHP9xiNxw5lwsyHDm", "duration_ms": \#($0)}"# } ?? "null"
        return Data(#"{"is_playing": true, "currently_playing_type": "\#(type)", "item": \#(item)}"#.utf8)
    }

    @Test func playingTrackMatchesTheSongsDuration() {
        let data = Self.currentlyPlaying(type: "track", durationMs: 195_057)
        #expect(SpotifyAPI.playingTrackURI(in: data, songDuration: 195.058) == "spotify:track:53IKYcHP9xiNxw5lwsyHDm")
    }

    /// Another device's track, or the previous track right after a change.
    @Test func playingTrackWithAnotherDurationIsNotTheSong() {
        let data = Self.currentlyPlaying(type: "track", durationMs: 195_057)
        #expect(SpotifyAPI.playingTrackURI(in: data, songDuration: 256.116) == nil)
        #expect(SpotifyAPI.playingTrackURI(in: data, songDuration: nil) == nil)
    }

    @Test func nothingPlayingOrNotATrackHasNoTrack() {
        #expect(SpotifyAPI.playingTrackURI(in: Data(), songDuration: 195) == nil)
        #expect(SpotifyAPI.playingTrackURI(in: Self.currentlyPlaying(type: "ad", durationMs: nil), songDuration: 30) == nil)
        #expect(SpotifyAPI.playingTrackURI(in: Self.currentlyPlaying(type: "episode", durationMs: 195_000), songDuration: 195) == nil)
    }

    @Test func libraryContainsReadsTheOneValue() {
        #expect(SpotifyAPI.isInLibrary(Data("[false]".utf8)) == false)
        #expect(SpotifyAPI.isInLibrary(Data("[true]".utf8)) == true)
        #expect(SpotifyAPI.isInLibrary(Data("[]".utf8)) == nil)
        #expect(SpotifyAPI.isInLibrary(Data(#"{"error": {"status": 403}}"#.utf8)) == nil)
    }

    @Test func libraryURLPassesTheURIAsQuery() {
        #expect(
            SpotifyAPI.libraryURL(for: "spotify:track:53IKYcHP9xiNxw5lwsyHDm").absoluteString
                == "https://api.spotify.com/v1/me/library?uris=spotify:track:53IKYcHP9xiNxw5lwsyHDm")
    }

    @Test func refreshWithoutRefreshTokenKeepsThePreviousOne() throws {
        let response = try JSONDecoder().decode(
            SpotifyAPI.TokenResponse.self,
            from: Data(#"{"access_token": "new", "token_type": "Bearer", "expires_in": 3600, "scope": ""}"#.utf8))
        let now = Date(timeIntervalSince1970: 0)
        let token = response.token(previousRefreshToken: "old-refresh", receivedAt: now)
        #expect(token == SpotifyAPI.Token(accessToken: "new", refreshToken: "old-refresh", expiresAt: now.addingTimeInterval(3600)))
        #expect(response.token(previousRefreshToken: nil, receivedAt: now) == nil)
        #expect(token?.needsRefresh(at: now.addingTimeInterval(3539)) == false)
        #expect(token?.needsRefresh(at: now.addingTimeInterval(3541)) == true)
    }

    @Test func callbackReadsTheQueryOfTheCallbackPath() {
        let request = Data("GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:53682\r\n\r\n".utf8)
        #expect(LoopbackCallback.query(ofRequest: request) == ["code": "abc", "state": "xyz"])
        #expect(LoopbackCallback.query(ofRequest: Data("GET /favicon.ico HTTP/1.1\r\n\r\n".utf8)) == nil)
        #expect(LoopbackCallback.query(ofRequest: Data("GET /callback?error=access_denied&state=xyz HTTP/1.1\r\n\r\n".utf8)) == ["error": "access_denied", "state": "xyz"])
    }
}
