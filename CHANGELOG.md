# Changelog

## 0.7.0

### Features

- Read the config from ~/.config/sill/config.toml and follow XDG_CONFIG_HOME
- Read the usage from codexbar serve and show its pace, plan and extra usage
- Show when each window resets in the usage popup, not the bar's short countdown
- Run as a hidden instance below the desktop picture with SILL_HIDDEN_INSTANCE
- Add hidden-sill.sh to build, start, capture and quit a hidden instance per checkout
- Start a hidden instance with every widget on the bar
- Crop a hidden instance's captures to what is drawn
- Replace barik's app icon with a Liquid Glass icon from Icon Composer

### Fixes

- Truncate a long song title instead of moving the now playing widget into the more widget
- Truncate a long event name instead of moving other widgets into the more widget
- Keep the scroll view from cutting off the shadows of popups with their own glass modules
- Stop codexbar serve before Sill exits, and keep its PID file until it does
- Keep a hidden instance from showing the config alert, calendar prompts or VoiceOver announcements
- Keep a hidden instance's codexbar serve PID file in its own directory
- Show the window switcher's overlay scroller in the popup's padding
- Print usage from axpress and axscroll when their arguments are missing
- Show Sill's copyright instead of barik's leftover Pansy

## 0.6.0

### Features

- Read now playing from media-control instead of AppleScript
- Add position option to place the bar at the bottom
- Add a Claude Code and Codex usage widget
- Add a volume widget with a Control Center style slider
- Add a front app widget
- Add a liquid-glass option for widget backgrounds and popups
- Make bar widgets and playback controls accessible buttons
- Center widgets on the bar between two center markers
- Make the glass bar widgets react to the pointer
- Rebuild glass popups as Liquid Glass modules that follow the system appearance
- Make the remaining widgets accessible
- Add a fixed-format option to the time widget
- Show widgets that do not fit on the bar in a more widget
- Render the bar's Liquid Glass as in an active window
- Let a widget use a system glass button to compare with its own glass
- Make every bar widget a system glass button with Liquid Glass
- Remove the look without Liquid Glass and require macOS 26
- Add AirPlay and opening the playing app to the now playing popup
- Lay out the now playing popup like the Now Playing screen
- Make the visible and VoiceOver strings localizable
- Add Japanese translations of the visible and VoiceOver strings
- Hide the bar while full-screen content is in front
- Open a window switcher from the front app widget
- Show app icons in the window switcher
- Log events and failures to the unified log
- Rename the app to Sill
- Add a script that prints the Homebrew cask for a release
- Release signed and attested builds and update the Homebrew tap
- Make this repository the Homebrew tap

### Fixes

- Open the now playing popup when no view variant is configured
- Show the front app right after Barik launches
- Show the now playing popup for streams without a timeline
- Fetch the artwork again when only the album changes
- Avoid overlapping runs of a slow usage command
- Match the now playing and time text to the other widgets on glass
- Align the usage popup's link icons with the headings
- Keep the bottom bar above windows
- Read the next event in the calendar button's accessibility value
- Keep keyboard focus rings while avoiding one when a popup opens
- Let Liquid Glass adapt the bar text instead of fixing it to the label color
- Keep centered widgets centered and clear of the side widgets
- Follow the system appearance only in popups that adapt to it
- Let the network, battery and changelog popups follow the system appearance
- Keep reloading the config after an editor replaces the file
- Import Combine where the time widget uses its timer publisher
- Serialize config reloads and keep retrying until a replaced file exists
- Read the Wi-Fi connection state in the network button's value
- Label usage windows by their length instead of their order
- Draw glass popups as dark glass like the Control Center
- Draw glass bar widgets as capsules like the now playing widget
- Keep a side that cannot fit off the centered widgets
- Draw glass bar widgets as dark glass with the system theme
- Keep fixed-format as written with the 12-hour time setting
- Keep each side's more widgets reachable
- Fade glass popups out with their window
- Force the active glass look only with Liquid Glass enabled
- Cancel a popup's pending hide or content switch when the next one starts
- Place popups with a layout so the first frame is in place
- Show the material popup when it appears, like the glass popup
- Close popups with Escape
- Tell VoiceOver when a popup opens
- Keep the bar and its popups on the primary screen's full frame
- Show the bar only once the config file is applied
- Draw nothing for center markers outside the centered layout
- Hide a side moved off the bar from VoiceOver
- Share each widget's manager between the copies of the widget
- Add the calendar full access usage description
- Drop every empty calendar name from the allow and deny lists
- Observe the calendar manager in the time widget and calendar popups
- Fetch calendar events on store and day changes instead of polling
- Show the next upcoming event, skipping canceled and declined ones
- Move the calendar popup to the new day and explain denied access
- Use the configured time zone across the calendar and show event dates
- Cache the time widget's formatters and tick at the format's resolution
- Estimate the playback position from microsecond timestamps
- Stop republishing the song every half second for its position
- Keep looking for media-control and bound its artwork fetch
- Store fetched artwork only for the track it belongs to
- Fetch artwork once at a time and a few times per track
- Clear the album art when a track has none
- Keep the aspect ratio when resizing cached images
- Show hours in long playback times and hide a zero-length timeline
- Show a nothing playing state when playback ends in an open popup
- Limit the title and artist lines in the horizontal now playing popup
- Leave out an empty artist in the now playing widget and popup
- Stop waiting for the usage command's child processes to close its output
- Run the usage command only while a usage widget is shown
- Offer only the volume controls the output device lets apps set
- Follow system time zone changes in the calendar manager
- Publish artwork only with the track it was fetched for
- Rewrite popup view variants without corrupting the config
- Write popup view variants on the config watch queue
- Back off while the config file is missing
- Show config errors found after launch on the bar
- Use the real keys in the generated default config
- Remove Config.theme, which defaulted to light
- Use one blur default and report blur values out of range
- Merge inline widget tables with the global ones key by key
- Run Barik as an agent app without a settings window
- Remove the unused settings popup variant
- Show an available popup variant instead of an empty popup
- Make popup variant buttons reachable by keyboard and VoiceOver
- Share one app updater between the update banners
- Quit for an update only after the update was started
- Install updates over the running app and keep it on failure
- Stop this modified build from offering upstream updates
- Keep the What's new banner until it is dismissed
- Match the changelog heading of the exact version
- Read the changelog bundled with the app
- Give the What's new banner text enough contrast
- Close multi-line TOML strings that end with quotes
- Stage an update next to the installed app before replacing it
- Time out window manager CLI calls and check their exit status
- Run one spaces fetch at a time and publish only changes
- Poll spaces once a second and fetch them on workspace notifications
- Pick the spaces provider again when apps launch or the config changes
- Keep the order the window manager lists spaces in
- Keep the focused space on the bar when it has no windows
- Focus a clicked window without sleeping on the main thread
- Remove the space hover state that changed nothing
- Truncate window titles by width instead of character count
- Tell VoiceOver which space and window are focused
- Show floating yabai windows and hide minimized ones
- Cache app icons by process identifier
- Keep a connected Wi-Fi without a network name apart from no Wi-Fi
- Derive the Wi-Fi state from CoreWLAN instead of the primary path
- Share the network widget's view model with its popup
- Use the same network icon colors in the widget and the popup
- Read only the internal battery and hide the widget without one
- Update the battery on power source notifications instead of every second
- Let the low battery text color reach the percentage
- Tell VoiceOver when the Mac is plugged in but not charging
- Share the battery manager with the popup and describe it to VoiceOver
- Use the configured battery levels in the popup
- Hide the front app icon from VoiceOver
- Start the Ethernet state hidden until its monitor reports
- Check the focused yabai space when a focus command runs
- Publish the spaces again when a window's icon is found
- Notice a spaces CLI installed at the same path later
- Use the system menu bar font for single-line bar text
- Size bar widgets to the bar height so they keep their background
- Put the trailing side's widgets in the leading more widget when it cannot fit
- Keep the calendar popup's text legible on glass
- Fit the widest speaker symbol in the volume widget
- Open, close and switch every popup with one transition like a system popover
- Switch popup layouts with a cross-fade instead of a blur
- Show the volume with one speaker symbol in variable color
- Fade glass popups in and out instead of scaling them
- Let clicks between bar widgets reach the app behind the bar
- Draw the usage logos as custom symbols sized by the text
- Size each system glass button like the widget next to it
- Keep widgets without glass when widget backgrounds are turned off
- Draw popups in the appearance the theme setting chooses
- Show only regular apps in the front app widget
- Apply a changed theme to an open popup
- Read the song with the button that opens the playing app
- Center the AirPlay button and keep the now playing popup on screen
- List every AirPlay device as soon as the AirPlay button is clicked
- Show any usage percentage without crashing
- Write the calendar's month heading in the locale's order
- Keep the minutes of event times on the hour
- Limit the artwork image cache
- Scroll any popup that would be taller than the screen
- Keep external commands from blocking or outliving Barik
- Avoid scaling, flipping and blurring with Reduce Motion
- Show a placeholder for a song without artwork
- Make popup controls easier to click and to use with VoiceOver
- Make an open calendar popup follow config reloads
- Save config changes without truncating or overwriting the file
- Give every popup the same padding and heading style
- Materialize popups with their own glass modules like the others
- Say so in the window switcher when a window cannot be focused
- Hide the bar for full-screen windows with a separate toolbar window
- Build popup content once instead of in ViewThatFits candidates
- Stop a release before the build when the version cannot be right

### Performance

- Read the usage every 30 seconds instead of every 5

## 0.5.1

> This release was supported by **ALinuxPerson** _(help with the appearance configuration, 1 issue)_, **bake** _(1 issue)_ and **Oery** _(1 issue)_

- Added yabai.path and aerospace.path config properties
- Fixed popup design
- Fixed Apple Music integration in Now Playing widget
- Added experimental appearance configuration:

```toml
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
blur = 3                                     # background type: from 1 to 6 for blur intensity
```

## 0.5.0

![Header](https://github.com/user-attachments/assets/182e7930-feb8-4e46-a691-7a54028d21a1)

> This release was supported by **AltaCursor** _([2 cups of coffee](https://ko-fi.com/mocki_toki), 3 issues)_ and **farhanmansurii** _(help with Spotify player)_

**Popup** — a new feature that allows opening an extended and interactive view of a widget (e.g., the battery charge indicator widget) by clicking on it. Currently, popups are available for the following **barik** widgets: Now Playing, Network, Battery, and Time (Calendar).

We want to make **barik** more useful, powerful, and convenient, so feel free to share your ideas in [Issues](https://github.com/mocki-toki/barik/issues/new), and contribute your work through [Pull Requests](https://github.com/mocki-toki/barik/pulls). We’ll definitely review everything!

Other changes:

- Added a new **Now Playing** widget — allowing control of music in desktop applications like Apple Music and Spotify. We welcome your suggestions for supporting other music services: https://github.com/mocki-toki/barik/issues/new
- More customization: Space key and title visibility, as well as a list of applications that will always be displayed by application name.
- Added the ability to switch windows and spaces by mouse click.
- Fixed the `calendar.show-events` config property functionality.
- Fixed screen resolution readjust
- Added auto update functionality, what's new popup

## 0.4.1

> This release was supported by **Oery** _(1 issue)_

- Fixed a display issue with the Notch.

## 0.4.0

> This release was supported by **AltaCursor** _(2 issues)_

- Added support for the `~/.barik-config.toml` configuration file.
- Added AeroSpace support 🎉.
- Fixed 24-hour time format.
- Fixed a desktop icon display issue.

## 0.3.0

- Added a network widget (Wi-Fi/Ethernet status).
- Fixed an incorrect color in the events indicator.
- Prioritized displaying events that are not all-day events.
- Added a maximum length for the focused window title.
- Updated the application icon.
- Added power plug battery status.

## 0.2.0

- Added support for a light theme.
- Added the application icon.

## 0.1.0

- Initial release.
