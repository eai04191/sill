import Foundation
import os

/// Sill's records in the unified log, one category for each part. Unlike printing to standard output, which is
/// buffered when it goes to a file and so loses its last lines when the process crashes, the unified log keeps every
/// record with its time and process, next to the system's own records of the same moment.
///
/// Events and failures are logged at the default level and errors at the error level, which the system keeps on disk.
/// Read them with:
///
///     /usr/bin/log show --last 1h --predicate 'subsystem == "net.mizle.sill"'
///
/// In zsh, `log` alone is a shell builtin, so the path is spelled out.
///
/// Window titles and file contents are logged as private, which the log shows as `<private>` unless private data
/// logging is enabled; identifiers, counts, durations and errors are public.
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "net.mizle.sill"

    /// Launch, termination and the bar's visibility.
    static let app = Logger(subsystem: subsystem, category: "App")
    /// Showing and hiding popups.
    static let popup = Logger(subsystem: subsystem, category: "Popup")
    /// Full-screen content in front, which hides the bar.
    static let fullscreen = Logger(subsystem: subsystem, category: "Fullscreen")
    /// Reading, watching and writing the config file.
    static let config = Logger(subsystem: subsystem, category: "Config")
    /// Commands stopped because they hung or printed too much (see `ProcessStopper`).
    static let commands = Logger(subsystem: subsystem, category: "Commands")
    /// The window switcher and the AeroSpace commands it runs.
    static let windowSwitcher = Logger(subsystem: subsystem, category: "WindowSwitcher")
    /// The now playing widget and media-control.
    static let nowPlaying = Logger(subsystem: subsystem, category: "NowPlaying")
    /// The usage widget and the CodexBar server it runs.
    static let usage = Logger(subsystem: subsystem, category: "Usage")
    /// The volume widget.
    static let volume = Logger(subsystem: subsystem, category: "Volume")
    /// The battery widget.
    static let battery = Logger(subsystem: subsystem, category: "Battery")
    /// The calendar in the time widget.
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
}

/// Seconds since `start`, for logging how long a step took.
func secondsSince(_ start: ContinuousClock.Instant) -> Double {
    let duration = ContinuousClock.now - start
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
