# CastGauge

CastGauge is a macOS menu bar app. It shows the health of a Chrome tab cast to a Cast device.
It also sets the Chrome mirror quality when Chrome starts.

## What it shows

- The menu bar shows a colored dot and the live rate from Chrome to the TV.
  - Green: no loss and a normal delay.
  - Orange: the delay or the delay variation goes up.
  - Red: the link loses packets.
  - Gray: no cast.
- The panel shows the rate against the maximum, the delay, the loss, and the Mac Wi-Fi signal.
- The Quality card sets the maximum rate (5 to 20 Mbit/s), the buffer (100 to 1000 ms), and the
  frame rate (30 or 60 fps).

## How the quality settings work

Chrome reads these values only at launch. "Apply and restart Chrome" quits Chrome in the normal
way (the same as Cmd-Q) and starts it again with:

| Value | Chrome launch input |
|---|---|
| Maximum rate | `--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/<n>` |
| 60 fps | `CastStreaming60fps` in the same `--enable-features` list |
| Buffer | environment variable `CHROME_MIRRORING_PLAYOUT_DELAY=<ms>` |
| Marker | `--castgauge-playout-delay=<ms>`. Chrome ignores it. CastGauge reads it back. |

Chrome 154 has all of these. The Chrome default maximum is 5 Mbit/s.

If you later open Chrome from the Dock, Chrome uses its defaults again. The panel then shows
"Not active in Chrome".

## How it measures

- The rate: `nettop`, for the Chrome flows to the TV. Chrome sends the cast stream from an
  unconnected UDP socket, so CastGauge also counts unconnected Chrome UDP flows.
- The delay and the loss: `ping` to the TV, over the last 30 replies.
- The TV: Bonjour (`_googlecast._tcp`). The TV reports `rs=Chrome Mirroring` during a mirror.
- The Mac Wi-Fi: CoreWLAN.

CastGauge needs the Local Network permission. macOS can ask again after each rebuild, because
the app has an ad-hoc signature.

## Build and test

These scripts need only the Command Line Tools. They use the macOS 26.5 SDK.

```sh
scripts/build-app.sh          # builds dist/CastGauge.app
scripts/run.sh                # builds a debug app and opens it
scripts/test.sh               # runs the unit tests
CASTGAUGE_LIVE_TV=192.168.1.155 scripts/test.sh --filter Live   # checks with the real TV
dist/CastGauge.app/Contents/MacOS/CastGauge --snapshot panel.png [--dark] [--expanded]
```

## Not in version 1

- Sound control. The test soundbar connects over optical and uses infrared, so the Mac cannot
  reach it.
- The TV Wi-Fi signal. A later version can read it with a Google Home local token or the
  Android TV debug link.

The fonts are Roboto Flex (SIL Open Font License) and Material Symbols Rounded (Apache 2.0).
Their licenses are in `Resources/Fonts`.
