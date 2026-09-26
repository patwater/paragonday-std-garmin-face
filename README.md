# Horizon Time — Garmin Watch Face
### A Paragon Day / Horizon Time implementation for the Fenix 5X Plus

---

## What This Does

This watch face implements the **Horizon Time** standard from
[Paragonday Systems](https://paragonday.systems/). Instead of displaying
an arbitrary clock reading tied to a time zone, it anchors time to the
actual solar day at your location using the four-label protocol:

**Daytime** (sunrise → sunset):
- `+H:MM pastrise` — elapsed time since sunrise
- `-H:MM tilset`   — countdown until sunset

**Nighttime** (sunset → next sunrise):
- `+H:MM pastset`  — elapsed time since sunset
- `-H:MM tilrise`  — countdown until next sunrise

The face shows both readings simultaneously. The primary (large, accented)
reading is the countdown to the *next* horizon event; the secondary (smaller,
dimmer) reading shows elapsed time since the *last* horizon event. Together
they place you precisely in the arc at a glance.

The face also shows today's sunrise/sunset, first light / last light
(civil twilight, sun 6° below the horizon), a battery strip, and a **sun-dial
ring** around the bezel.

![Horizon Time on the Fenix 5X Plus (simulator)](docs/watchface.png)

### Display layout (240×240 round)

```
     ^06:42   18:45v     ← sunrise / sunset
      06:17   19:10      ← first light / last light
     -8:31 tilrise       ← primary: countdown to next horizon event
     +3:26 pastset       ← secondary: elapsed since last event
          ▬▬             ← battery
```

### The ring

The ring is a 24-hour sun dial (360° = 24 h). **Solar noon is at the top**
(true solar transit, not 12:00 on the clock) and the green dot moves clockwise, so sunrise sits near 9 o'clock, sunset
near 3 o'clock (shifting with the seasons), and night runs along the bottom.
The thin white ring is the day; the thick **orange** arcs mark first light →
sunrise and sunset → last light. Because it is a continuous loop, the dot
never resets at sunrise or sunset.

Colors shift between **amber** (daytime) and **steel blue** (night) for the
text.

---

## Project Structure

```
├── manifest.xml                      ← Connect IQ app manifest
├── monkey.jungle                     ← Build config (SDK 9.x)
├── source/
│   ├── HorizonTimeApp.mc             ← App entry point
│   ├── HorizonTimeView.mc            ← Watch face drawing / layout
│   └── SunCalc.mc                    ← Solar position + Horizon Time math
├── resources/
│   ├── strings/strings.xml
│   └── drawables/                    ← drawables.xml + launcher_icon.png
└── docs/watchface.png                ← simulator screenshot
```

---

## Building and Sideloading

### Prerequisites

1. **Garmin Connect IQ SDK** (built against 9.2) via the SDK Manager:
   https://developer.garmin.com/connect-iq/sdk/
   In the SDK Manager, also download the **fenix 5X Plus** device.
2. **Java** (JRE 17 is fine) on your `PATH` — the compiler needs it.
3. A **developer key** (`developer_key.der`). Generate one in VS Code
   (**Monkey C: Generate a Developer Key**) or with OpenSSL:
   ```bash
   openssl genrsa -out key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out developer_key.der -nocrypt
   ```
   Keep it out of the repo (`*.der` is git-ignored).
4. Optional: **VS Code** + the **Monkey C** extension (by Garmin).

### Build with VS Code

Open this folder, press `Ctrl+Shift+P` → **Monkey C: Build Current Project**,
and pick `fenix5xplus`. The `.prg` appears in `bin/`.

### Build with CLI

```bash
$CIQ_SDK/bin/monkeyc \
  -f monkey.jungle \
  -o bin/horizon-time.prg \
  -d fenix5xplus \
  -y /path/to/developer_key.der \
  -w
```

`$CIQ_SDK` is the SDK folder, e.g.
`%APPDATA%\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-<version>`.

### Run in the simulator

```bash
$CIQ_SDK/bin/connectiq          # start the simulator
$CIQ_SDK/bin/monkeydo bin/horizon-time.prg fenix5xplus
```

### Sideload to the watch

Connect the watch over USB and copy `bin/horizon-time.prg` into
`GARMIN/APPS/`. On Windows the watch is an MTP device (no drive letter):
in File Explorer open **This PC → fenix 5X Plus → Primary → GARMIN → Apps**.
Eject, unplug, then hold the middle-left button → **Watch Face** →
**Horizon Time** → **Apply**.

Garmin Express does not list or install sideloaded apps.

---

## Location

Watch faces cannot request GPS themselves. The face reads the watch's
**last known position** (`Position.getInfo()`) when the day rolls over — the
position is whatever the watch last stored from an activity or another app.
Until one is available it uses the **La Crescenta default**
(34.23°N, 118.23°W). Compass and elevation are not shown: watch faces have
no access to the `Sensor` module.

---

## The Math: How Horizon Time is Calculated

The solar algorithm (`SunCalc.mc`) is the USNO/Astronomical Almanac method,
chosen because it fits in the Connect IQ memory budget and needs no external
calls:

1. **Day of year** computed from calendar date.
2. **Mean anomaly** → **true longitude** → **right ascension**.
3. **Declination** → **local hour angle** (90.833° zenith for
   sunrise/sunset with atmospheric refraction).
4. Event time converted to UTC epoch seconds. For western longitudes the
   sunset lands on the next UTC day, so it is shifted by +24 h when it
   would otherwise precede sunrise.

`Time.now()` is already Unix epoch seconds, so no epoch offset is applied.
Solar noon is computed directly from the sun's transit (not from sunrise/sunset), so the ring keeps its orientation in polar day/night. Note that adding two 2026 epoch
timestamps overflows Monkey C's 32-bit `Number`.

Horizon Time itself:

```
-- Daytime --
pastSecs = now − sunrise
tilSecs  = sunset − now

-- Nighttime --
pastSecs = now − lastSunset
tilSecs  = nextSunrise − now

-- Ring --
dotDeg   = (now − solarNoon) / 240   [° clockwise from 12 o'clock, wrapped ±180]
```

---

## Customization Ideas

| What to change | Where |
|---|---|
| Default lat/lng | `HorizonTimeView.mc` `_lat`, `_lng` |
| Day/night accent colors | `HorizonTimeView.mc` `accentColor` |
| Ring radius / thickness | `HorizonTimeView.mc` `ringR`, `setPenWidth` |
| Twilight arc color | `HorizonTimeView.mc` `twilightColor` |
| Reading fonts | `HorizonTimeView.mc` `FONT_NUMBER_*` / `FONT_SMALL` |

---

## References

- [Paragonday Systems](https://paragonday.systems/) — Horizon Time standard
- [Garmin Connect IQ API](https://developer.garmin.com/connect-iq/api-docs/)
- [MonkeyC Language Reference](https://developer.garmin.com/connect-iq/monkey-c/)
- [SunTimes CIQ widget](https://github.com/simonl-ciq/SunTimes) — inspiration for solar calc approach
- [SunCalc CIQ by haraldh](https://github.com/haraldh/SunCalc) — reference implementation
