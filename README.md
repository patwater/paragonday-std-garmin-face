# Horizon Time — Garmin Watch Face
### A Paragon Day / Horizon Time implementation for the Fenix 5X Plus

---

## What This Does

This watch face implements the **Horizon Time** standard from
[Paragonday Systems](https://paragonday.systems/). Instead of displaying
an arbitrary clock reading tied to a time zone, it anchors time to the
actual solar day at your location using the four-label protocol:

**Daytime** (sunrise → sunset):
- `+HH:MM pastrise` — elapsed time since sunrise
- `-HH:MM tilset`   — countdown until sunset

**Nighttime** (sunset → next sunrise):
- `+HH:MM pastset`  — elapsed time since sunset
- `-HH:MM tilrise`  — countdown until next sunrise

The face shows both readings simultaneously. The primary (large, accented)
line is the countdown to the *next* horizon event; the secondary (smaller,
dimmer) line shows elapsed time since the *last* horizon event. Together
they place you precisely in the arc at a glance.

The face also shows standard clock time, today's sunrise/sunset, and a
visual arc-progress bar that sweeps across the top of the display.

### Display layout (240×240 px)

```
        Wed Sep 25
  ════════════◉══════   ← arc progress bar (sun dot)
     -2:18 tilset       ← primary: countdown to next horizon event
   +9:44 pastrise       ← secondary: elapsed since last event
  ↑06:14         18:47↓ ← local sunrise / sunset
        16:05           ← standard clock
           ▓▓▓▓▓▓░░     ← battery bar
```

Colors shift between **amber** (daytime) and **steel blue** (night).

---

## Project Structure

```
horizon-time-watchface/
├── manifest.xml                      ← Connect IQ app manifest
├── source/
│   ├── HorizonTimeApp.mc             ← App entry point, GPS handler
│   ├── HorizonTimeView.mc            ← Watch face drawing / layout
│   └── SunCalc.mc                    ← Solar position + Horizon Time math
└── resources/
    ├── strings/strings.xml
    └── drawables/drawables.xml
```

---

## Building and Sideloading

### Prerequisites

1. Install **Garmin Connect IQ SDK** (≥ 7.4):
   https://developer.garmin.com/connect-iq/sdk/

2. Install **VS Code** + the **Monkey C** extension (by Garmin), or use
   the standalone `connectiq` CLI tools.

3. You need the **Fenix 5X Plus** device key from the SDK's
   `devices/fenix5xPlus/` folder (included with the SDK install).

### Build with VS Code

1. Open the `horizon-time-watchface/` folder in VS Code.
2. Press `Cmd/Ctrl+Shift+P` → **Monkey C: Build Current Project**.
3. Select `fenix5xPlus` as the target device.
4. The `.prg` file appears in `bin/`.

### Build with CLI

```bash
# Set your SDK path
export CIQ_SDK=/path/to/connectiq-sdk

$CIQ_SDK/bin/monkeyc \
  -f manifest.xml \
  -o bin/horizon-time.prg \
  -d fenix5xPlus \
  -y /path/to/developer_key.der \
  source/HorizonTimeApp.mc \
  source/HorizonTimeView.mc \
  source/SunCalc.mc
```

### Sideload to watch

```bash
# With watch connected via USB and Garmin Express running:
$CIQ_SDK/bin/monkeydo bin/horizon-time.prg fenix5xPlus
```

Or use the **Garmin Connect app** on your phone:
1. Transfer `horizon-time.prg` to the watch's `GARMIN/APPS/` folder.
2. Restart the watch; select the face from the watch face gallery.

---

## Location / GPS

On first launch the face requests a one-shot GPS fix. Until the fix
arrives it uses the **La Crescenta default** (34.23°N, 118.23°W) which
is close enough for testing in the San Gabriel foothills.

After the fix, solar data is recalculated once per day. The watch
remembers the last GPS position across app restarts because it uses
`Position.LOCATION_ONE_SHOT` on each launch — the Fenix 5X Plus
caches almanac data so subsequent fixes are fast.

---

## The Math: How Horizon Time is Calculated

The solar algorithm (`SunCalc.mc`) is a clean-room MonkeyC
implementation of the USNO/Astronomical Almanac method, chosen
because it fits in the Connect IQ memory budget and requires no
external calls:

1. **Day of year** computed from calendar date.
2. **Mean anomaly** → **true longitude** → **right ascension**.
3. **Declination** → **local hour angle** (using 90.833° zenith for
   civil sunrise/sunset with atmospheric refraction).
4. Local event time converted to UTC epoch seconds.

Horizon Time itself:

```
-- Daytime --
pastSecs = now − sunrise
tilSecs  = sunset − now
arcFill  = pastSecs / (sunset − sunrise)   [0–1, for progress bar]
display  = "−H:MM tilset"  (primary)
           "+H:MM pastrise" (secondary)

-- Nighttime (after sunset) --
pastSecs = now − sunset
tilSecs  = nextSunrise − now
arcFill  = pastSecs / (nextSunrise − sunset)
display  = "−H:MM tilrise" (primary)
           "+H:MM pastset"  (secondary)
```

---

## Customization Ideas

| What to change | Where |
|---|---|
| Default lat/lng | `HorizonTimeView.mc` lines `_lat`, `_lng` |
| Day/night accent colors | `HorizonTimeView.mc` `accentColor` assignments |
| Arc bar position/size | `HorizonTimeView.mc` `barY`, `barW` constants |
| Font size of Horizon label | Change `FONT_NUMBER_HOT` to another system font |
| Show steps / HR instead of battery | Replace `_drawBatteryDot()` call |

---

## References

- [Paragonday Systems](https://paragonday.systems/) — Horizon Time standard
- [Garmin Connect IQ API](https://developer.garmin.com/connect-iq/api-docs/)
- [MonkeyC Language Reference](https://developer.garmin.com/connect-iq/monkey-c/)
- [SunTimes CIQ widget](https://github.com/simonl-ciq/SunTimes) — inspiration for solar calc approach
- [SunCalc CIQ by haraldh](https://github.com/haraldh/SunCalc) — reference implementation
