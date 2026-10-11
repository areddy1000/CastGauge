# CastGauge: design

Date: 2026-10-11

## Intent

The user casts a Chrome tab to a Chromecast with Google TV (HD). The web site has no Cast app,
so Chrome mirrors the tab. The video often buffers. The user does not know the cause.

CastGauge is a small macOS menu bar app. It does two things:

1. It shows live values that tell the user why the cast slows down.
2. It lets the user set the Chrome mirror quality by hand. Chrome does not decide alone.

## Facts found before the design

These facts come from measurements on the user's Mac and from the Chromium source.

- The Mac runs Google Chrome 154.0.8037.98.
- The TV is "Bedroom TV" at 192.168.1.155. It announces `_googlecast._tcp` with `md=Chromecast`.
  During a cast, its TXT record has `rs=Chrome Mirroring`.
- Chrome sent about 5 Mbit/s to the TV during a cast. Chrome caps the mirror video at 5 Mbit/s
  by default.
- The cap comes from the feature `CastStreamingMaxVideoBitrate` (enabled by default) with the
  parameter `max_bitrate_mbps` (default 5). Source: `media/base/media_switches.cc` and
  `components/mirroring/service/mirror_settings.cc`.
- Chrome reads the environment variable `CHROME_MIRRORING_PLAYOUT_DELAY` (1 to 65535 ms). It sets
  the receiver buffer time.
- `mirror_settings.cc` checks a feature `kCastStreaming60fps` for 60 fps. The default is 30 fps.
  The exact feature string is not confirmed. See "Open items for the builder".
- The maximum mirror resolution is 1080p. No setting changes it.
- The Mac is on 5 GHz, Wi-Fi 6, signal -51 dBm.
- A ping to the TV: 0% loss, 5.6 ms average, 0.8 ms deviation.
- The TV refuses `/setup/eureka_info` on port 8008 and 8443 with HTTP 403. It needs a local
  auth token from the Google Home cloud.
- The router is a Verizon Fios Router at 192.168.1.1.

## Goals

- A menu bar item that always shows the live data rate from Chrome to the TV.
- A panel that opens from the item and shows all values and the quality controls.
- Quality controls that restart Chrome with the chosen settings.
- A code structure that the AppleTv app can use later.

## Non-goals

- No sound control in version 1. See "Sound control".
- The first version has no history graph. Add it later only if the live values do not show the
  cause of a stall.
- The first version does not read the TV Wi-Fi signal. The panel shows a place for it.
- No change to the Chromecast.
- No change to Chrome files on disk, Chrome preferences, or `chrome://flags`.
- No custom Chrome build and no custom Cast sender.
- No merge into the AppleTv app now.

## Anti-goals

These results make the app a failure, even if it works:

- The app restarts Chrome without a confirmation from the user.
- The app uses the Google account of the user, or asks for a Google password.
- The app works around a missing macOS permission. If a permission is missing, the app tells the
  user and stops that feature.
- The app shows a value that it guessed as if it measured it.

## Constraints

- Swift 6 and SwiftUI. macOS 15 or later.
- Swift Package Manager only. This Mac has no Xcode. Every swift command needs
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- Ad-hoc code signature. No Developer ID identity exists.
- Follow the build and bundle method of `/Users/Apple/Code/AppleTv` (`scripts/build-app.sh`,
  `Resources/Info.plist`). Reuse it where it fits.
- The repository is `/Users/Apple/Code/CastGauge`.
- Code comments, docstrings and commit messages use ASD-STE100 Simplified Technical English rules.
  See `~/.claude/CLAUDE.md`.

## Structure (decided)

- A library product, `CastGaugeKit`, holds all measurement and Chrome-control code. It has no UI
  and no package dependencies. Its API is `public`, so that the AppleTv app can add it later as
  a local path package. Tests cover the kit. (Designer's call after the review.)
- An executable target, `CastGauge`, holds the SwiftUI menu bar app (`MenuBarExtra`, window
  style panel). It is a menu-bar-only app (`LSUIElement`).

## The menu bar item (decided)

- It shows a colored dot and the data rate, for example "● 4.9 Mbit/s".
- Gray: no cast is active.
- Green: the link has no loss and a normal delay. A rate below the maximum alone is not a
  warning. The encoder sends less for still content, also on a clean link.
- Yellow: the delay or the delay variation goes up, or the rate falls suddenly while the delay
  goes up.
- Red: the link loses packets.
- The exact limits for each color are the builder's call. Put them in one place, so that they
  are easy to tune. (Designer's call after the review.)

## Visual design (decided)

The user wants the app to feel like a Google app, not like a makeshift tool.

- Use Material 3: tonal color roles from one seed color (Google blue, `#0B57D0`), surface
  containers, 28 pt panel corners, 16 pt card corners, filled and tonal buttons, state layers on
  hover and press.
- Support light and dark mode with the Material 3 dark color roles.
- Icons: Material Symbols Rounded (Apache 2.0). Bundle the font or SVGs in the app.
- Font: Roboto Flex (SIL Open Font License). Bundle it. Do not use Google Sans.
- No Google logo and no Google product names in the app. It must not claim that Google made it.
- One panel only. No tabs and no second window. The user chose this.
- The reference mockup is "A: One panel with cards". A copy of it is in
  `docs/superpowers/specs/2026-10-11-material-panel-mockup.html`. Leave out its Sound card.
- Motion follows Material 3 easing (emphasized, about 300 to 500 ms for expand and collapse).

## The panel (decided)

From top to bottom:

1. **Header:** a round TV icon, the TV name, the cast state ("Casting a Chrome tab"), and a
   status chip ("Good", "Unstable", "Losing data", "Not casting") with the same color logic as
   the menu bar dot.
2. **Connection card:** the data rate as a large number against the maximum, with a linear bar.
   Below it, three tiles: delay, packet loss, Mac Wi-Fi signal (dBm and band). A fourth value,
   the TV Wi-Fi signal, shows "not set up" in version 1.
3. **Quality card:** collapsed, it shows a summary ("12 Mbit/s · 400 ms · 30 fps"). A click
   expands it in place in the same panel. It does not open a new page.

Quality controls (inside the expanded Quality card):

- Maximum rate: 5 to 20 Mbit/s, whole numbers. Default 5 (the Chrome default).
- Buffer: 100 to 1000 ms. Default 400 ms. (The user accepted these ranges. They were the
  designer's guess.)
- Frame rate: 30 or 60.
- An "Apply and restart Chrome" button. It shows a confirmation first. The text says that the
  cast stops, that Chrome reopens the tabs, and that the user must start the cast again.
- The panel shows if the running Chrome uses the chosen settings or not. Read the command line of
  the running Chrome process to find out. If the user later quits and opens Chrome from the Dock,
  the settings are lost, and the panel must show that.
- macOS does not let the app read the Chrome environment. So the app also adds a marker switch,
  `--castgauge-playout-delay=<ms>`, to the command line. Chrome ignores unknown switches. The
  panel reads the buffer value from this marker. (Designer's call after the review.)

## Sound control (out of version 1)

The user wanted volume buttons, like the AppleTv app. Tests on 2026-10-11 showed that the app
cannot control the volume of this setup:

- The Cast receiver reports `volume_control_type: fixed`. It refuses Cast volume commands.
- The Android TV Remote protocol (ports 6466 and 6467) paired, and it accepted `VOLUME_DOWN`
  and `VOLUME_UP`. The soundbar did not move. The TV reports volume level 0 of 0.
- The soundbar connects over optical, not HDMI. The remote controls it with infrared. A Mac
  has no infrared transmitter.

Do not build sound control. The user said to leave it for now.

## How each value gets measured (decided at the source level)

| Value | Source |
|---|---|
| Cast state and TV name | Bonjour browse for `_googlecast._tcp`. Read `fn` and `rs` from TXT. |
| TV address | Resolve the Bonjour service. |
| Data rate to the TV | Mac network counters for Chrome flows to the TV address only. |
| Delay and loss | Repeated ICMP echo to the TV. |
| Mac Wi-Fi | CoreWLAN: RSSI, noise, channel band. |
| TV Wi-Fi | Not in version 1. |

Notes:

- The mirror traffic comes from a Chrome helper process (`Google Chrome Helper`). Count the bytes
  that go to the TV address, not all Chrome traffic. All Chrome traffic includes uploads to the
  internet.
- The data rate in the measurement above came from `nettop -P` for the whole Chrome helper.
  That is not exact enough for the app.

## Chrome restart (decided)

1. The user confirms.
2. The app quits Chrome with `NSRunningApplication.terminate()`. This is a normal quit, the same
   as Cmd-Q, so Chrome saves the session. It needs no Automation permission. Do not add an
   Apple event entitlement. (The user chose this method.)
3. The app waits until Chrome exits. If Chrome does not exit in a reasonable time, the app stops
   and tells the user. It does not force quit Chrome.
4. The app starts Chrome with `open -a "Google Chrome" --env CHROME_MIRRORING_PLAYOUT_DELAY=<ms>
   --args --restore-last-session --enable-features=<features>`.
5. The features string is `CastStreamingMaxVideoBitrate:max_bitrate_mbps/<n>`, plus the 60 fps
   feature when the user selects 60.
6. The app saves the chosen settings in `UserDefaults`.

## Later versions (not in version 1)

Leave a clean place in `CastGaugeKit` for a TV signal source. Two sources are possible:

- The Android TV debug link: the user turns on network debugging on the TV, and the app reads the
  Wi-Fi state over ADB.
- The Google Home local auth token: the user gives the token, and the app reads
  `/setup/eureka_info` on port 8443 with the token in a header.

The user said they will provide the Google Home key later.

## Open items for the builder

These are the builder's calls unless the text says otherwise:

- Confirm the exact 60 fps feature string in the Chromium source for Chrome 154. If no such
  feature exists in that version, hide the frame rate control and say so in the panel.
- Confirm that `CastStreamingMaxVideoBitrate:max_bitrate_mbps/<n>` works. A test: apply 12, cast
  a tab with motion, and measure a rate above 5 Mbit/s. Check `chrome://version` for the command
  line.
- Choose how to read per-flow byte counts (for example `nettop` per flow, or a system API).
- Choose how to send the ICMP echo (for example `/sbin/ping`, or an unprivileged ICMP socket).
- Choose the update interval. About 1 second is a sensible start.
- Choose the color limits for the menu bar dot.
- macOS can ask for the Local Network permission for Bonjour. CoreWLAN can need Location Services
  for some values. If macOS refuses a permission, show that in the panel and ask the user. Do not
  build a workaround.
