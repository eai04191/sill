import AppKit
import Foundation
import Network
import os

enum SpotifyError: Error {
    /// No token, or Spotify no longer accepts it: the user has to sign in again.
    case signedOut
    /// Another sign-in already listens on the callback port, such as one in another Sill.
    case callbackPortInUse
    /// The user denied access, or the callback did not come back from the request Sill made.
    case authorizationFailed(String)
    case http(Int)
}

/// Signs in to Spotify and sends requests with the user's token.
///
/// Signing in opens Spotify's consent page in the default browser, which redirects to `127.0.0.1` with the code;
/// Sill listens there only during the sign-in. Listening on the loopback address showed no permission prompt
/// (measured with the firewall off).
///
/// The tokens are kept in a file only the user can read rather than in the Keychain: Sill is signed with a
/// self-signed certificate and no team, so its Keychain items are bound to the exact build, and every update or
/// rebuild asked for the login password before reading them (measured); the data protection keychain, which does
/// not ask, needs a team (`errSecMissingEntitlement`). Other processes of the user can read the file. The token can
/// only read what is playing and read and change the Liked Songs, and the user can revoke it in Spotify's account
/// settings.
@MainActor
final class SpotifyAccount {
    static let shared = SpotifyAccount()

    /// The token file. A hidden instance keeps its own, so it never replaces the token of the maintainer's Sill.
    private static let tokenFileURL: URL? =
        (HiddenInstance.directory
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "net.mizle.sill", isDirectory: true))?
        .appendingPathComponent("spotify-token.json")

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    private var token: SpotifyAPI.Token?
    private var loadedToken = false
    /// The refresh in progress. Spotify may replace the refresh token on every refresh, so requests at once wait for
    /// one refresh instead of each using the same refresh token.
    private var refreshTask: Task<SpotifyAPI.Token, Error>?

    var isSignedIn: Bool { currentToken() != nil }

    // MARK: Signing in

    func signIn(clientID: String) async throws {
        let verifier = SpotifyAPI.makeCodeVerifier()
        let state = SpotifyAPI.makeState()
        let url = SpotifyAPI.authorizationURL(
            clientID: clientID, codeChallenge: SpotifyAPI.codeChallenge(for: verifier), state: state)
        let query = try await LoopbackCallback.receive(port: SpotifyAPI.callbackPort) {
            NSWorkspace.shared.open(url)
        }
        guard query["state"] == state else { throw SpotifyError.authorizationFailed("state mismatch") }
        guard let code = query["code"] else {
            throw SpotifyError.authorizationFailed(query["error"] ?? "no code")
        }
        let request = SpotifyAPI.tokenRequest([
            "grant_type": "authorization_code", "code": code, "redirect_uri": SpotifyAPI.redirectURI,
            "client_id": clientID, "code_verifier": verifier,
        ])
        let token = try await Self.requestToken(request, previousRefreshToken: nil)
        save(token)
        Logger.nowPlaying.notice("Signed in to Spotify")
    }

    // MARK: Requests

    /// Sends a request with the access token, refreshing it first when it is about to expire, and once more when
    /// Spotify rejects it.
    func send(_ request: URLRequest, clientID: String) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await send(request, token: try await validToken(clientID: clientID))
        guard response.statusCode == 401 else { return (data, response) }
        return try await send(request, token: try await refresh(clientID: clientID))
    }

    private func send(_ request: URLRequest, token: SpotifyAPI.Token) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }

    private func validToken(clientID: String) async throws -> SpotifyAPI.Token {
        guard let token = currentToken() else { throw SpotifyError.signedOut }
        return token.needsRefresh(at: Date()) ? try await refresh(clientID: clientID) : token
    }

    private func refresh(clientID: String) async throws -> SpotifyAPI.Token {
        if let refreshTask { return try await refreshTask.value }
        guard let current = currentToken() else { throw SpotifyError.signedOut }
        let task = Task { () throws -> SpotifyAPI.Token in
            let request = SpotifyAPI.tokenRequest([
                "grant_type": "refresh_token", "refresh_token": current.refreshToken, "client_id": clientID,
            ])
            return try await Self.requestToken(request, previousRefreshToken: current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let token = try await task.value
            save(token)
            return token
        } catch SpotifyError.http(let status) where status == 400 || status == 401 {
            // invalid_grant: the refresh token was revoked, or belongs to another client ID.
            Logger.nowPlaying.error("Spotify rejected the refresh token (HTTP \(status, privacy: .public)); signing out")
            signOut()
            throw SpotifyError.signedOut
        }
    }

    private static func requestToken(_ request: URLRequest, previousRefreshToken: String?) async throws -> SpotifyAPI.Token {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else { throw SpotifyError.http(response.statusCode) }
        let tokenResponse = try JSONDecoder().decode(SpotifyAPI.TokenResponse.self, from: data)
        guard let token = tokenResponse.token(previousRefreshToken: previousRefreshToken, receivedAt: Date()) else {
            throw SpotifyError.authorizationFailed("no refresh token")
        }
        return token
    }

    // MARK: Token file

    private func currentToken() -> SpotifyAPI.Token? {
        if !loadedToken {
            loadedToken = true
            if let url = Self.tokenFileURL, let data = try? Data(contentsOf: url) {
                token = try? JSONDecoder().decode(SpotifyAPI.Token.self, from: data)
            }
        }
        return token
    }

    private func save(_ token: SpotifyAPI.Token) {
        self.token = token
        loadedToken = true
        guard let url = Self.tokenFileURL, let data = try? JSONEncoder().encode(token) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Written to a new file created with mode 0600 and renamed over the old one, so the token is never in a
            // file others can read, even for a moment.
            let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
            guard FileManager.default.createFile(
                atPath: temporaryURL.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            guard rename(temporaryURL.path, url.path) == 0 else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            Logger.nowPlaying.error("Could not save the Spotify token: \(String(describing: error), privacy: .public)")
        }
    }

    private func signOut() {
        token = nil
        loadedToken = true
        if let url = Self.tokenFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Receives the one redirect of a sign-in on a loopback port.
enum LoopbackCallback {
    /// How long the consent page may stay open before the sign-in is given up.
    private static let timeout: TimeInterval = 300

    /// Listens on `127.0.0.1:port`, calls `onReady` once listening, and returns the query of the first request.
    @MainActor
    static func receive(port: UInt16, onReady: @escaping @MainActor () -> Void) async throws -> [String: String] {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completion = Completion(listener: listener, continuation: continuation)
                // The listener and its connections report on the main queue (`start(queue: .main)`).
                listener.stateUpdateHandler = { state in
                    MainActor.assumeIsolated {
                        switch state {
                        case .ready:
                            onReady()
                        case .failed(.posix(.EADDRINUSE)):
                            completion.finish(.failure(SpotifyError.callbackPortInUse))
                        case .failed(let error):
                            completion.finish(.failure(error))
                        case .cancelled:
                            completion.finish(.failure(CancellationError()))
                        default:
                            break
                        }
                    }
                }
                listener.newConnectionHandler = { connection in
                    connection.start(queue: .main)
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, _ in
                        let query = data.flatMap(Self.query(ofRequest:))
                        let page = query == nil ? "Sill could not read this request." : "You can close this tab and return to Sill."
                        let body = Data("<!doctype html><meta charset=utf-8><title>Sill</title><p>\(page)</p>".utf8)
                        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
                        // A request without the callback's query, such as for a favicon, leaves the sign-in waiting.
                        if let query {
                            MainActor.assumeIsolated { completion.finish(.success(query)) }
                        }
                    }
                }
                listener.start(queue: .main)
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    completion.finish(.failure(SpotifyError.authorizationFailed("timed out")))
                }
            }
        } onCancel: {
            listener.cancel()
        }
    }

    /// Resumes the sign-in once, with the first of the callback, a failure, the cancellation and the timeout.
    @MainActor
    private final class Completion {
        private let listener: NWListener
        private var continuation: CheckedContinuation<[String: String], Error>?

        init(listener: NWListener, continuation: CheckedContinuation<[String: String], Error>) {
            self.listener = listener
            self.continuation = continuation
        }

        func finish(_ result: Result<[String: String], Error>) {
            guard let continuation else { return }
            self.continuation = nil
            listener.cancel()
            continuation.resume(with: result)
        }
    }

    /// The query of a request to the callback path, from its request line, such as `GET /callback?code=… HTTP/1.1`.
    static func query(ofRequest data: Data) -> [String: String]? {
        guard let line = String(decoding: data, as: UTF8.self).split(separator: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
            let components = URLComponents(string: String(parts[1])), components.path == "/callback"
        else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value
        }
        return query
    }
}
