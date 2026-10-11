# CastGauge

CastGauge is a macOS menu bar app. It shows the health of a Chrome tab cast to a Cast device.
It also sets the Chrome mirror quality when Chrome starts.

## What it shows

- The menu bar shows the TV icon and the TV name. During a tab mirror, a dot on the icon shows
  the health:
  - Green: no loss and a normal delay.
  - Orange: the delay or the delay variation goes up.
  - Red: 2 or more of the last 10 pings got no reply.
- When the Cast device runs a known app (for example YouTube), the menu bar shows the app icon
  and the media title that the device reports. CastGauge only reads this status on port 8009.
  It never sends a playback command.
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
| No remoting at 60 fps | `--disable-features=MediaRemoting` |
| Marker | `--castgauge-playout-delay=<ms>`. Chrome ignores it. CastGauge reads it back. |

At 60 fps, the test TV (Chromecast with Google TV) did not answer the "remoting" offer. Chrome
uses remoting for the "optimize fullscreen video" mode. With no answer, Chrome stopped the cast.
Plain mirroring at 60 fps worked, so a 60 fps launch also turns remoting off.

Chrome 154 has all of these. The Chrome default maximum is 5 Mbit/s.

If you later open Chrome from the Dock, Chrome uses its defaults again. The panel then shows
"Not active in Chrome".

## How it measures

- The rate: the upload byte counter of the network interface that reaches the TV, read once
  per second. It needs no helper process. It counts all the Mac uploads on that interface;
  during a tab cast, the cast stream is almost all of them. (Version 1 used `nettop`, which cost
  more than one CPU core during a cast.)
- The delay and the loss: `ping` to the TV, over the last 10 replies.
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

## Background cost

CastGauge runs all day, so it idles at almost no cost:

- With no tab cast and a closed panel, no timer runs. Bonjour tells the app about changes.
- A connection to a Cast device is open only while that device runs an app, such as YouTube.
  The Bonjour record already shows an idle device.
- During a tab cast, a 1 s tick reads one byte counter and the last `ping` result.
- The panel values and the Wi-Fi read update only while the panel shows.
- Each retry waits longer after each failure, up to 5 minutes.

The menu bar item shows only while a Chromecast is on the network. The first launch turns on
Open at Login. The panel footer has a switch for it.

The icon font is a subset with only the icons that the app uses. To add an icon, run
`scripts/subset-icons.py` on the full Material Symbols Rounded font with the new list of names.

## Not in version 1

- Sound control. The test soundbar connects over optical and uses infrared, so the Mac cannot
  reach it.
- The TV Wi-Fi signal. A later version can read it with a Google Home local token or the
  Android TV debug link.

The fonts are Roboto Flex (SIL Open Font License) and Material Symbols Rounded (Apache 2.0).
Their licenses are in `Resources/Fonts`.
