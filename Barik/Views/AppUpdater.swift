import Foundation

final class AppUpdater: ObservableObject {
    /// One updater for the whole app: the bar can show several update banners (one per layout candidate and in the
    /// "more" popup), and each would otherwise check GitHub on its own.
    static let shared = AppUpdater()

    // Published properties to notify the UI
    @Published var latestVersion: String?
    @Published var updateAvailable = false

    // Local path for the downloaded update directory
    private(set) var downloadedUpdatePath: String?
    // URL for the update asset obtained from GitHub release JSON
    private var updateAssetURL: URL?

    // Timer to schedule periodic update checks
    private var updateTimer: Timer?

    private init() {
        fetchLatestRelease()
        // Check for updates every 30 minutes
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: 1800, repeats: true
        ) { [weak self] _ in
            self?.fetchLatestRelease()
        }
    }

    deinit {
        updateTimer?.invalidate()
    }

    /// Returns a fallback download URL based on the version string.
    private func fallbackDownloadURL(for version: String) -> URL? {
        let versionWithoutPrefix =
            version.hasPrefix("v") ? String(version.dropFirst()) : version
        let urlString =
            "https://github.com/mocki-toki/barik/releases/download/\(version)/barik-v\(versionWithoutPrefix).zip"
        return URL(string: urlString)
    }

    /// Fetches the latest release information from GitHub and updates the state.
    func fetchLatestRelease() {
        guard
            let url = URL(
                string:
                    "https://api.github.com/repos/mocki-toki/barik/releases/latest"
            )
        else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error = error {
                print("Error fetching release info: \(error)")
                return
            }
            guard let data = data,
                let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                let tag = json["tag_name"] as? String
            else {
                return
            }

            // Attempt to extract the asset download URL if available
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                        name.hasSuffix(".zip"),
                        let downloadURLString = asset["browser_download_url"]
                            as? String,
                        let assetURL = URL(string: downloadURLString)
                    {
                        self?.updateAssetURL = assetURL
                        break
                    }
                }
            }

            let currentVersion = VersionChecker.currentVersion ?? "0.0.0"
            let comparisonResult =
                self?.compareVersion(tag, currentVersion) ?? 0
            DispatchQueue.main.async {
                self?.latestVersion = tag
                self?.updateAvailable = comparisonResult > 0
            }
        }.resume()
    }

    /// Compares two version strings.
    /// - Returns: 1 if v1 > v2, -1 if v1 < v2, and 0 if equal.
    func compareVersion(_ v1: String, _ v2: String) -> Int {
        let version1 = v1.replacingOccurrences(of: "v", with: "")
        let version2 = v2.replacingOccurrences(of: "v", with: "")
        let parts1 = version1.split(separator: ".").compactMap { Int($0) }
        let parts2 = version2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let num1 = i < parts1.count ? parts1[i] : 0
            let num2 = i < parts2.count ? parts2[i] : 0
            if num1 > num2 { return 1 }
            if num1 < num2 { return -1 }
        }
        return 0
    }

    /// Why an update could not be downloaded or installed.
    struct UpdateError: LocalizedError {
        let errorDescription: String?

        init(_ description: String) {
            errorDescription = description
        }
    }

    /// Downloads and unzips the update archive.
    /// - Parameters:
    ///   - version: The latest version string.
    ///   - completion: Returns the temporary directory URL containing the unzipped app, or why there is none.
    private func downloadAndUnzip(
        latest version: String, completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let assetURL: URL
        if let url = updateAssetURL {
            assetURL = url
        } else if let fallbackURL = fallbackDownloadURL(for: version) {
            assetURL = fallbackURL
        } else {
            completion(.failure(UpdateError("Invalid update URL")))
            return
        }

        print("Downloading update from: \(assetURL.absoluteString)")
        let downloadTask = URLSession.shared.downloadTask(with: assetURL) {
            localURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                let status = (response as? HTTPURLResponse)?.statusCode
                completion(.failure(UpdateError("Download failed with HTTP status \(status.map(String.init) ?? "unknown")")))
                return
            }
            guard let localURL = localURL else {
                completion(.failure(UpdateError("No update file found")))
                return
            }

            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            do {
                try fileManager.createDirectory(
                    at: tempDir, withIntermediateDirectories: true,
                    attributes: nil)
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(
                    fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = [
                    "-o", localURL.path, "-d", tempDir.path,
                ]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                let newAppURL = tempDir.appendingPathComponent("Barik.app")
                if unzipProcess.terminationStatus != 0 {
                    completion(.failure(UpdateError("Unzipping failed with status \(unzipProcess.terminationStatus)")))
                } else if fileManager.fileExists(atPath: newAppURL.path) {
                    completion(.success(tempDir))
                } else {
                    completion(.failure(UpdateError("Barik.app not found in the update archive")))
                }
            } catch {
                completion(.failure(error))
            }
        }
        downloadTask.resume()
    }

    /// Downloads the update and starts installing it, which replaces the app once it has quit.
    /// - Parameters:
    ///   - version: The latest version string.
    ///   - completion: Called on the main thread once the installation has started, so the app should quit, or with
    ///     why the update could not be downloaded or installed.
    func downloadAndInstall(
        latest version: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        downloadAndUnzip(latest: version) { [weak self] result in
            let installResult = result.flatMap { tempDir in
                Result {
                    guard let self else { throw UpdateError("The updater is gone") }
                    self.downloadedUpdatePath = tempDir.path
                    try self.installUpdate(latest: version)
                }
            }
            if case .failure(let error) = installResult {
                print("Error updating: \(error)")
            }
            DispatchQueue.main.async {
                completion(installResult)
            }
        }
    }

    /// Installs the update by replacing the running application where it is installed, once it has quit.
    /// - Parameter version: The latest version string.
    func installUpdate(latest version: String) throws {
        guard let downloadedPath = downloadedUpdatePath else {
            throw UpdateError("No downloaded update to install")
        }
        let newAppURL = URL(fileURLWithPath: downloadedPath)
            .appendingPathComponent("Barik.app")
        // The installed app is moved aside rather than deleted first, and moved back if the new app cannot be moved
        // in, so a failed update keeps the old app.
        let script = """
            #!/bin/bash
            pid="$1"
            new_app="$2"
            app="$3"
            backup="$app.previous-$$"
            while kill -0 "$pid" 2>/dev/null; do
                sleep 0.2
            done
            if mv "$app" "$backup"; then
                if mv "$new_app" "$app"; then
                    rm -rf "$backup"
                else
                    mv "$backup" "$app"
                fi
            fi
            open "$app"
            rm -- "$0"
            """

        let fileManager = FileManager.default
        let updateTempDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(
            at: updateTempDir, withIntermediateDirectories: true,
            attributes: nil)
        let scriptURL = updateTempDir.appendingPathComponent("update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = [
            String(ProcessInfo.processInfo.processIdentifier), newAppURL.path, Bundle.main.bundleURL.path,
        ]
        try process.run()
    }
}
