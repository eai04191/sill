> [!WARNING]
> Sill is heavily vibe-coded. For now, I make it for my own use, so I don’t accept feature requests. **Claude Code** handles a project like this well, so if you need something Sill doesn’t do, fork it and make it yourself.

----

# Sill

**Sill** is a lightweight macOS menu bar replacement with Liquid Glass, built for macOS 26. It sits at the top or bottom of the screen.

Sill is a fork of [barik](https://github.com/mocki-toki/barik) by Simon Butenko, reworked to follow the Human Interface Guidelines and Liquid Glass, with a window switcher, a Now Playing widget for any player, and fewer features to maintain. It does not read barik's config file.

## Requirements

- macOS 26+ on Apple silicon
- Xcode, to build it yourself

## Quick Start

1. Install Sill with Homebrew:

```sh
brew tap eai04191/sill https://github.com/eai04191/sill
brew install --cask eai04191/sill/sill
```

This repository is the tap. Update Sill with `brew upgrade --cask sill`. Sill is not notarized, so the cask removes the quarantine attribute after installing.

Or build Sill and copy it to your Applications folder:

```sh
xcodebuild -project Sill.xcodeproj -scheme Sill -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/Sill.app ~/Applications/Sill.app
```

2. Hide the system menu bar in **System Settings** and uncheck **Desktop & Dock → Show items → On Desktop**.

3. Launch **Sill** from the Applications folder.

4. Add **Sill** to your login items for automatic startup.

## Configuration

When you launch **Sill** for the first time, it will create `~/.config/sill/config.toml` (`$XDG_CONFIG_HOME/sill/config.toml` when `XDG_CONFIG_HOME` is set) with an example customization for your new menu bar. Sill no longer reads `~/.sill-config.toml`; move it there if you have one.

```toml
theme = "system" # system, light, dark

[widgets]
displayed = [ # widgets on menu bar
    "default.nowplaying",
    "default.battery",
    # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
    "default.time",
]

[widgets.default.battery]
show-percentage = true
warning-level = 30
critical-level = 10

[widgets.default.time]
format = "E d, J:mm"
# fixed-format = "MM/dd HH:mm" # a fixed pattern used as is (in English) instead of the localized format
calendar.format = "J:mm"

calendar.show-events = true
# calendar.allow-list = ["Home", "Personal"] # show only these calendars
# calendar.deny-list = ["Work", "Boss"] # show all calendars except these

[widgets.default.time.popup]
view-variant = "box"



### EXPERIMENTAL, WILL BE REPLACED BY STYLE API IN THE FUTURE
[experimental.foreground] # settings for menu bar
height = "default"        # available values: default (55.0), menu-bar (height like system menu bar), <float> (e.g., 40, 33.5)
horizontal-padding = 25   # padding on the left and right corners
spacing = 15              # spacing between widgets
```

### More options

```toml
position = "bottom"   # top (default) or bottom; popups open upward at the bottom

[widgets]
displayed = [
    "default.nowplaying", # now playing from media-control (`brew install media-control`), any player incl. browsers
    "center",             # widgets between two "center" markers stay at the center of the bar
    "default.frontapp",   # frontmost app icon and name; click it for the window switcher (needs AeroSpace)
    "center",
    "default.usage",      # Claude Code / Codex usage
    "default.volume",     # output volume with a slider popup
]

[widgets.default.usage]
command = "~/.local/bin/usage-display.sh" # prints {"claude": {"primary": {"pct": 10, "reset": "2h"}, "secondary": ...}, "codex": ...}

[widgets.default.volume]
show-percentage = true

[widgets.default.frontapp]
show-icon = true
```

With `theme = "system"` (the default), the bar is dark glass with white text even in Light Mode, so it stays legible on any wallpaper; only `theme = "light"` makes it light. Popups follow `theme`, and with `"system"` the system appearance.

With `position = "bottom"`, the bar does not reserve space on the screen like the Dock does, so maximized windows extend under it.

## What to do if the currently playing song is not displayed in the Now Playing widget?

The Now Playing widget reads the system-wide now playing session through [media-control](https://github.com/ungive/media-control), so it shows any player that reports to Now Playing in Control Center, including browsers such as Firefox. Install it with Homebrew:

```sh
brew install media-control
```

Sill looks for it in `/opt/homebrew/bin` and `/usr/local/bin` and picks it up within 30 seconds of installing it, without a restart. If a player is still not shown, check that it appears in Control Center's Now Playing and that `media-control get` prints it.

## Window Switcher

Clicking the front app widget opens a window switcher, a replacement for Mission Control: a menu of the windows on every workspace, grouped by app, with the workspace of each window. Type to filter the windows by title, app or workspace, move with the Up and Down keys, and press Return or click to focus a window; Escape closes it.

The switcher lists and focuses windows through the [AeroSpace](https://github.com/nikitabobko/AeroSpace) CLI, so it needs AeroSpace running, and no extra permission for Sill. Sill looks for `aerospace` in `/opt/homebrew/bin` and `/usr/local/bin`, and the switcher says so when it is not available.

## Where Are the Menu Items?

Menu items (such as File, Edit, View, etc.) are not supported. You can use [Raycast](https://www.raycast.com/), which supports menu items through an interface similar to Spotlight. barik's author uses it with the `option + tab` shortcut, and it works very well.

If you’re accustomed to using menu items from the system menu bar, simply move your mouse to the top of the screen to reveal the system menu bar, where they will be available.

<img src="resources/raycast-menu-items.jpeg" alt="Raycast Menu Items">

## License

[MIT](LICENSE). Sill keeps barik's copyright notice, as the license asks.

## Trademarks

Apple and macOS are trademarks of Apple Inc. This project is not connected to Apple Inc. and does not have their approval or support.
