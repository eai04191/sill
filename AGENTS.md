# Sill

Sill is a macOS 26 menu bar replacement in SwiftUI, a fork of [barik](https://github.com/mocki-toki/barik). `origin` is the fork (eai04191/sill) and `upstream` is barik, which is no longer maintained; changes are not sent back to it.

## Design

- Follow the Human Interface Guidelines and Liquid Glass, and cite the HIG or Apple's documentation for design decisions. When the documentation does not settle a question, measure the behavior on the real machine before deciding.
- Bar widgets that open a popup use `barWidgetButton` (Sill/Utils/BarButton.swift): the system glass button (`.buttonStyle(.glass)`, capsule), so every widget has the same press feedback. Controls inside popups use `barButton`, a plain button. Do not add a custom pressed style.
- The regular glass button adds 12 pt of padding on the sides and 4 pt above and below its label (measured). `GlassButtonInset` in Sill/Utils/ExperimentalConfigurationModifier.swift subtracts it so widgets keep the bar's height.
- Do not put glass on glass: a popup whose content draws its own glass modules passes `providesGlassModules: true` to `MenuBarPopup.show`, and the popup then adds no glass behind them.
- Popups appear with `.opacity` and the glass materializes (`liquidGlassMaterializes`). Do not use `.scale` on glass: the glass slides instead of growing.
- Do not decide a glass's variant from state that a preference writes into `@State` after layout: nested glass then does not materialize when it is inserted (reproduced in a minimal app). Pass such facts in as init arguments instead.
- Popups follow the `theme` setting through the window appearance (`MenuBarPopup.applyAppearance`). Do not fix a color scheme or text color unless asked.
- The bar hides while the active app has a window covering the bar's screen (Sill/Utils/FullscreenDetector.swift). A native full-screen window has its toolbar in a separate window in front of it, and other apps' small windows can be in front, so the check looks at all the active app's windows, not only the frontmost one.

## Code

- User-visible text is localized in Sill/Resources/Localizable.xcstrings (English source, Japanese translation). Add each new key in place without re-sorting the file: letting Xcode rewrite it reorders every entry and buries the change in the diff.
- Log with the `Logger` categories in Sill/Utils/Log.swift, not `print`. Read the log with `/usr/bin/log show --last 1h --predicate 'subsystem == "net.mizle.sill"'`: in zsh, `log` alone is a shell builtin and reads nothing.
- External tools are looked up in /opt/homebrew/bin and /usr/local/bin on every use: `media-control` for Now Playing, `aerospace` for the window switcher and `codexbar` for the usage widget. Say in the UI when one is missing.

## Build and check

- Build: `xcodebuild -project Sill.xcodeproj -scheme Sill -configuration Release -derivedDataPath build build`.
- The maintainer installs it with `make install-sill-dev` from the dotfiles repository (eai04191/dotfiles), which signs it with a local self-signed certificate so permissions such as calendar access survive rebuilds.
- Check UI changes on the real machine, not only by building. The scripts in scripts/verify synthesize input and list windows; build one with `swiftc -o <output> scripts/verify/<name>.swift`. Use `move` to hover rather than `click` at guessed coordinates, which can click into other apps. Record the screen with `screencapture -v` and measure transitions frame by frame, for example with ffmpeg's `signalstats` filter.
- The maintainer uses the Mac while Sill is checked, and moving the pointer takes it from them: ask before using `move`, `click`, `press` or `scroll`. Open popups with `axpress` and scroll them with `axscroll`, which go through the accessibility API and leave the pointer alone. Glass reacts to hover only under the real pointer (a move sent only to Sill with `CGEvent.postToPid` did not light it), so hover needs the pointer.
- `nowplaying` publishes a now playing item, with a long title or as a live stream without a duration, and `backdrop` puts dense text behind the bar to show what the glass lets through.
- Do not change system settings such as Reduce Transparency; ask the maintainer to switch them, and to switch them back.
