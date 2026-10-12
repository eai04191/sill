import CryptoKit
import Foundation

/// The parts of the Spotify Web API (https://developer.spotify.com/documentation/web-api) used to show and change
/// whether the song playing in Spotify is in the user's Liked Songs.
///
/// Spotify's AppleScript reports the track's URI, but reading `starred` fails, and asking the app at all needs the
/// Automation permission; media-control reports no Spotify identifier. The URI is therefore taken from
/// `GET /me/player/currently-playing`, which needs no permission on the Mac.
enum SpotifyAPI {
    static let bundleIdentifier = "com.spotify.client"

    /// The redirect URI registered for the app in the Spotify developer dashboard. Spotify allows plain HTTP only for
    /// loopback addresses, and the port must match the registered URI.
    static let callbackPort: UInt16 = 53682
    static let redirectURI = "http://127.0.0.1:53682/callback"
    static let scopes = ["user-read-currently-playing", "user-library-read", "user-library-modify"]

    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let currentlyPlayingURL = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
    static let libraryURL = URL(string: "https://api.spotify.com/v1/me/library")!
    static let libraryContainsURL = URL(string: "https://api.spotify.com/v1/me/library/contains")!

    // MARK: Authorization (authorization code with PKCE)

    /// A code verifier of 86 characters from 64 random bytes, within the 43 to 128 characters RFC 7636 allows.
    static func makeCodeVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<64).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func makeState() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    /// The S256 code challenge of a verifier (RFC 7636, section 4.2).
    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authorizationURL(clientID: String, codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// A form-encoded request to the token endpoint, for exchanging the code or refreshing the token.
    static func tokenRequest(_ parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" unescaped in queries, which a form body reads as a space.
        request.httpBody = Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    /// The tokens kept between launches.
    struct Token: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date

        /// Refreshed a minute before it expires, so a request does not reach Spotify with an expired token.
        func needsRefresh(at date: Date) -> Bool {
            date.addingTimeInterval(60) >= expiresAt
        }
    }

    /// The token endpoint's response. A refresh may leave out the refresh token, which then stays the same; when it
    /// returns one, the previous one may no longer work.
    struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double

        func token(previousRefreshToken: String?, receivedAt date: Date) -> Token? {
            guard let refreshToken = refresh_token ?? previousRefreshToken else { return nil }
            return Token(accessToken: access_token, refreshToken: refreshToken, expiresAt: date.addingTimeInterval(expires_in))
        }
    }

    // MARK: Library

    /// The URI of the track Spotify reports as playing for the account, when it is the song Sill shows.
    ///
    /// The account may be playing on another device, and right after a track change Spotify can still report the
    /// previous track, so the reported track is compared with the song's duration from media-control. The names are
    /// not compared: Spotify returns them in the language of the request's `Accept-Language`, such as "Kenshi Yonezu"
    /// or "米津玄師" for the same artist (measured), and the app's language is not known. A response without content
    /// (204), an episode or an ad has no track.
    static func playingTrackURI(in data: Data, songDuration: Double?) -> String? {
        guard !data.isEmpty, let songDuration,
            let playing = try? JSONDecoder().decode(CurrentlyPlaying.self, from: data),
            playing.currently_playing_type == "track", let item = playing.item,
            abs(item.duration_ms / 1000 - songDuration) <= 1
        else { return nil }
        return item.uri
    }

    private struct CurrentlyPlaying: Decodable {
        let currently_playing_type: String?
        let item: Item?

        struct Item: Decodable {
            let uri: String
            let duration_ms: Double
        }
    }

    static func libraryContainsURL(for uri: String) -> URL {
        libraryURL(libraryContainsURL, uri: uri)
    }

    static func libraryURL(for uri: String) -> URL {
        libraryURL(libraryURL, uri: uri)
    }

    private static func libraryURL(_ base: URL, uri: String) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uris", value: uri)]
        return components.url!
    }

    /// Whether the one URI asked about is in the library, from `GET /me/library/contains`.
    static func isInLibrary(_ data: Data) -> Bool? {
        guard let values = try? JSONDecoder().decode([Bool].self, from: data), values.count == 1 else { return nil }
        return values[0]
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
