import AppKit
import os

/// A copy of Sill started for checking a build while the maintainer keeps using the Mac and their own Sill, with
/// `SILL_HIDDEN_INSTANCE` set in its environment to a directory of its own (scripts/verify/hidden-sill.sh sets it).
///
/// Its bar and popups sit below the desktop picture, so they are on screen for the window server and can be captured
/// one window at a time with `screencapture -l`, but nothing of them shows on the display. A window above the desktop
/// picture's level, `desktopWindow - 1` (measured on macOS 26), would show where no app window covers it; a window
/// outside every display cannot be captured at all.
///
/// Its popups are not made key, so opening one does not take keyboard focus from the active app. Escape then does not
/// reach the popup; close it by pressing its widget again.
///
/// Nothing else of it reaches the maintainer either: it never requests calendar access, so a signature that does
/// not match the maintainer's Sill fails in the log rather than with a permission prompt; it quits on a config error
/// without the alert; and its popups are not announced to VoiceOver.
///
/// Files that the maintainer's Sill keeps for itself, such as the codexbar serve PID file, go in that directory instead,
/// so a hidden instance does not replace them.
enum HiddenInstance {
    /// The instance's own directory, which must be an absolute path.
    static let directory: URL? = ProcessInfo.processInfo.environment["SILL_HIDDEN_INSTANCE"].map { path in
        // Exiting rather than crashing, as a crash would put the crash report dialog on the maintainer's screen.
        guard path.hasPrefix("/") else {
            Logger.app.error("SILL_HIDDEN_INSTANCE must be an absolute path to the instance's directory: \(path, privacy: .public)")
            exit(1)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var isEnabled: Bool { directory != nil }

    /// Below the desktop picture.
    static let windowLevel = Int(CGWindowLevelForKey(.desktopWindow)) - 2
}
