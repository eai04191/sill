**NOTICE**: Unfortunately, I don’t have much free time to actively maintain this project. If you like the project but are not satisfied with its current state, you can explore the many forks or create your own. Even if you’re unfamiliar with **Swift**, tools like **Claude Code** and **Codex** can effectively help implement projects like this. This is a great opportunity to tailor **barik** to your needs and make it exactly the way you’d like.

----

<p align="center" dir="auto">
  <img src="resources/header-image.png" alt="Barik"">
  <p align="center" dir="auto">
    <a href="LICENSE">
      <img alt="License Badge" src="https://img.shields.io/github/license/mocki-toki/barik.svg?color=green" style="max-width: 100%;">
    </a>
    <a href="https://github.com/mocki-toki/barik/issues">
      <img alt="Issues Badge" src="https://img.shields.io/github/issues/mocki-toki/barik.svg?color=green" style="max-width: 100%;">
    </a>
    <a href="CHANGELOG.md">
      <img alt="Changelog Badge" src="https://img.shields.io/badge/view-changelog-green.svg" style="max-width: 100%;">
    </a>
    <a href="https://github.com/mocki-toki/barik/releases">
      <img alt="GitHub Downloads (all assets, all releases)" src="https://img.shields.io/github/downloads/mocki-toki/barik/total">
    </a>
  </p>
</p>

**barik** is a lightweight macOS menu bar replacement.

<br>

<div align="center">
  <h3>Screenshots</h3>
  <img src="resources/preview-image-light.png" alt="Barik Light Theme">
  <img src="resources/preview-image-dark.png" alt="Barik Dark Theme">
</div>
<br>
<div align="center">
  <h3>Video</h3>
  <video src="https://github.com/user-attachments/assets/33cfd2c2-e961-4d04-8012-664db0113d4f">
</div>
    
https://github.com/user-attachments/assets/d3799e24-c077-4c6a-a7da-a1f2eee1a07f

<br>

## Requirements

- macOS 26+

## Quick Start

1. Install **barik** via [Homebrew](https://brew.sh/)

```sh
brew install --cask mocki-toki/formulae/barik
```

Or you can download from [Releases](https://github.com/mocki-toki/barik/releases), unzip it, and move it to your Applications folder.

2. Hide the system menu bar in **System Settings** and uncheck **Desktop & Dock → Show items → On Desktop**.

3. Launch **barik** from the Applications folder.

4. Add **barik** to your login items for automatic startup.

## Configuration

When you launch **barik** for the first time, it will create a `~/.barik-config.toml` file with an example customization for your new menu bar.

```toml
theme = "system" # system, light, dark

[widgets]
displayed = [ # widgets on menu bar
    "spacer",
    "default.nowplaying",
    "default.battery",
    "divider",
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
[experimental.background] # settings for blurred background
displayed = true          # display blurred background
height = "default"        # available values: default (stretch to full screen), menu-bar (height like system menu bar), <float> (e.g., 40, 33.5)
blur = 3                  # background type: from 1 to 6 for blur intensity, 7 for black color

[experimental.foreground] # settings for menu bar
height = "default"        # available values: default (55.0), menu-bar (height like system menu bar), <float> (e.g., 40, 33.5)
horizontal-padding = 25   # padding on the left and right corners
spacing = 15              # spacing between widgets

[experimental.foreground.widgets-background] # settings for widgets background
displayed = false                            # wrap widgets in their own background
```

### Additional options in this fork

```toml
position = "bottom"   # top (default) or bottom; popups open upward at the bottom

[widgets]
displayed = [
    "default.nowplaying", # now playing from media-control (`brew install media-control`), any player incl. browsers
    "center",             # widgets between two "center" markers stay at the center of the bar
    "default.frontapp",   # frontmost app icon and name
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

Currently, you can customize the order of widgets (time, indicators, etc.) and adjust some of their settings. Soon, you’ll also be able to add custom widgets and completely change **barik**'s appearance—making it almost unrecognizable (hello, r/unixporn!).

## Future Plans

I'm not planning to stick to minimal functionality—exciting new features are coming soon! The roadmap includes full style customization, the ability to create custom widgets or extend existing ones, and a public **Store** where you can share your styles and widgets.

Soon, you'll also be able to place widgets not just at the top, but at the bottom, left, and right as well. This means you can replace not only the menu bar but also the Dock! 🚀

## What to do if the currently playing song is not displayed in the Now Playing widget?

The Now Playing widget reads the system-wide now playing session through [media-control](https://github.com/ungive/media-control), so it shows any player that reports to Now Playing in Control Center, including browsers such as Firefox. Install it with Homebrew:

```sh
brew install media-control
```

Barik looks for it in `/opt/homebrew/bin` and `/usr/local/bin` and picks it up within 30 seconds of installing it, without a restart. If a player is still not shown, check that it appears in Control Center's Now Playing and that `media-control get` prints it.

## Where Are the Menu Items?

[#5](https://github.com/mocki-toki/barik/issues/5), [#1](https://github.com/mocki-toki/barik/issues/1)

Menu items (such as File, Edit, View, etc.) are not currently supported, but they are planned for future releases. However, you can use [Raycast](https://www.raycast.com/), which supports menu items through an interface similar to Spotlight. I personally use it with the `option + tab` shortcut, and it works very well.

If you’re accustomed to using menu items from the system menu bar, simply move your mouse to the top of the screen to reveal the system menu bar, where they will be available.

<img src="resources/raycast-menu-items.jpeg" alt="Raycast Menu Items">

## Contributing

Contributions are welcome! Please feel free to submit a PR.

## License

[MIT](LICENSE)

## Trademarks

Apple and macOS are trademarks of Apple Inc. This project is not connected to Apple Inc. and does not have their approval or support.

## Stars

[![Stargazers over time](https://starchart.cc/mocki-toki/barik.svg?variant=adaptive)](https://starchart.cc/mocki-toki/barik)
