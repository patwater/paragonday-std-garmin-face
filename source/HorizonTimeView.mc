// HorizonTimeView.mc — Main watch face rendering
// Fenix 5X Plus: 240×240 px, always-on capable
//
// Layout (Paragonday + compass + elevation):
//
//   ┌─────────────────────────┐
//   │         [DATE]          │  small, top
//   │   ══════ ARC BAR ══════  │  solar arc progress bar
//   │      -0:02 tilset       │  primary Paragonday reading
//   │    +12:02 pastrise      │  secondary Paragonday reading
//   │   ↑ 06:14   18:47 ↓    │  sunrise / sunset
//   │  [COMPASS]  [ELEVATION] │  heading needle + altitude ft
//   │        ▓▓▓▓▓▓░░         │  battery bar
//   └─────────────────────────┘

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Position;

class HorizonTimeView extends WatchUi.WatchFace {

    // Location (defaults to La Crescenta until GPS fix)
    var _lat      as Float   = 34.23;
    var _lng      as Float   = -118.23;
    var _altM     as Float?  = null;   // altitude in metres from GPS
    var _heading  as Float?  = null;   // magnetic heading in degrees (0–360)

    // Cached solar data (refreshed once per day)
    var _sunrise  as Number? = null;
    var _sunset   as Number? = null;
    var _lastDay  as Number  = -1;

    function initialize() {
        WatchFace.initialize();
    }

    function setLocation(lat as Float, lng as Float, altM as Float?) as Void {
        _lat     = lat;
        _lng     = lng;
        _altM    = altM;
        _lastDay = -1;
        WatchUi.requestUpdate();
    }

    function setHeading(heading as Float?) as Void {
        _heading = heading;
    }

    function onLayout(dc as Graphics.Dc) as Void {}

    function onUpdate(dc as Graphics.Dc) as Void {
        var now     = Time.now();
        var nowSecs = now.value();
        var unixNow = nowSecs + 631065600; // Garmin → Unix epoch

        var info  = Gregorian.info(now, Time.FORMAT_SHORT);
        var year  = info.year;
        var month = info.month;
        var day   = info.day;

        // Refresh solar once per day
        if (day != _lastDay) {
            var pInfo = Position.getInfo();
            if (pInfo.position != null && pInfo.accuracy >= Position.QUALITY_POOR) {
                var coords = pInfo.position.toDegrees();
                _lat = coords[0].toFloat();
                _lng = coords[1].toFloat();
                if (pInfo has :altitude && pInfo.altitude != null) {
                    _altM = pInfo.altitude.toFloat();
                }
            }
            var utcOffset = _estimateUtcOffset(unixNow, info);
            var solar     = SunCalc.compute(_lat, _lng, year, month, day, utcOffset);
            _sunrise = solar[:sunrise];
            _sunset  = solar[:sunset];
            _lastDay = day;
        }

        // Watch faces have no Sensor access; use last known GPS heading (radians)
        var hInfo = Position.getInfo();
        if (hInfo has :heading && hInfo.heading != null) {
            _heading = hInfo.heading.toFloat();
        }

        var cx = dc.getWidth()  / 2;  // 120
        var cy = dc.getHeight() / 2;  // 120

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var isDay = (_sunrise != null && _sunset != null)
                    ? (unixNow >= _sunrise && unixNow < _sunset)
                    : (info.hour >= 6 && info.hour < 20);

        var accentColor = isDay ? 0xC8922A : 0x7BA3C8;
        var dimColor    = 0x666666;
        var mutedColor  = 0x3A3A3A;

        // ── 1. Date ──────────────────────────────────────────────────────
        var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        var monNames = ["Jan","Feb","Mar","Apr","May","Jun",
                        "Jul","Aug","Sep","Oct","Nov","Dec"];
        var dateStr  = Lang.format("$1$ $2$ $3$",
            [dayNames[info.day_of_week - 1], monNames[month - 1], day.format("%02d")]);
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 10, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ── 2. Arc progress bar ──────────────────────────────────────────
        var barH = 6;
        var barW = 180;
        var barX = cx - barW / 2;
        var barY = 32;

        dc.setColor(mutedColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, barW, barH, 3);

        var arcFill   = 0.5f;
        var primLine  = "···";
        var secLine   = "···";
        if (_sunrise != null && _sunset != null) {
            var ht   = SunCalc.horizonTime(unixNow, _sunrise, _sunset);
            arcFill  = ht[:arcFill].toFloat();
            primLine = ht[:primaryLine];
            secLine  = ht[:secondLine];
        } else {
            arcFill = (info.hour * 3600 + info.min * 60).toFloat() / 86400.0;
        }
        var fillW = (arcFill * barW).toNumber();
        if (fillW < 6)  { fillW = 6; }
        if (fillW > barW) { fillW = barW; }
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, fillW, barH, 3);
        // Dot
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(barX + fillW, barY + barH / 2, 5);

        // ── 3. Paragonday readings ───────────────────────────────────────
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_NUMBER_MEDIUM, primLine,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 92, Graphics.FONT_SMALL, secLine,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ── 4. Sunrise / Sunset times ────────────────────────────────────
        var riseStr = "···";
        var setStr  = "···";
        if (_sunrise != null) { riseStr = _epochToLocalHHMM(_sunrise); }
        if (_sunset  != null) { setStr  = _epochToLocalHHMM(_sunset);  }
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(barX + 2,        120, Graphics.FONT_XTINY, "^" + riseStr,
                    Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(barX + barW - 2, 120, Graphics.FONT_XTINY, setStr + "v",
                    Graphics.TEXT_JUSTIFY_RIGHT);

        // ── 5. Compass (center-left) ─────────────────────────────────────
        _drawCompass(dc, 80, 162, 28, accentColor, dimColor, mutedColor);

        // ── 6. Elevation (center-right) ──────────────────────────────────
        _drawElevation(dc, 162, 148, accentColor, dimColor);

        // ── 7. Battery strip ─────────────────────────────────────────────
        _drawBattery(dc, cx, 228, accentColor);
    }

    // Compass rose drawn with polygons (no arc support in dc, use lines)
    // cx, cy = center; r = outer radius
    function _drawCompass(dc as Graphics.Dc, cx as Number, cy as Number,
                          r as Number, accent as Number,
                          dim as Number, muted as Number) as Void {
        // Outer ring
        dc.setColor(muted, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        dc.drawCircle(cx, cy, r - 2);

        // Cardinal tick marks
        var cardinals = [["N", 0], ["E", 90], ["S", 180], ["W", 270]];
        for (var i = 0; i < cardinals.size(); i++) {
            var label = cardinals[i][0];
            var angleDeg = cardinals[i][1].toFloat();
            var rad = angleDeg * Math.PI / 180.0;
            var ix = (cx + (r - 4) * Math.sin(rad)).toNumber();
            var iy = (cy - (r - 4) * Math.cos(rad)).toNumber();
            var ox = (cx + r * Math.sin(rad)).toNumber();
            var oy = (cy - r * Math.cos(rad)).toNumber();
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(ix, iy, ox, oy);
            // Label just inside the tick
            var lx = (cx + (r - 11) * Math.sin(rad)).toNumber();
            var ly = (cy - (r - 11) * Math.cos(rad)).toNumber();
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(lx, ly - 6, Graphics.FONT_XTINY, label,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Heading needle
        var headingRad = (_heading != null) ? _heading : 0.0f; // radians from GPS
        // North tip (accent)
        var nx = (cx + (r - 8) * Math.sin(headingRad)).toNumber();
        var ny = (cy - (r - 8) * Math.cos(headingRad)).toNumber();
        // South tail
        var sx = (cx - (r - 14) * Math.sin(headingRad)).toNumber();
        var sy = (cy + (r - 14) * Math.cos(headingRad)).toNumber();
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, cy, nx, ny);
        dc.fillCircle(nx, ny, 3);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, cy, sx, sy);

        // Center pivot dot
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 3);

        // Heading degrees label
        var hdgDeg = (_heading != null)
            ? (((_heading * 180.0 / Math.PI).toNumber() % 360 + 360) % 360)
            : 0;
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + r + 3, Graphics.FONT_XTINY,
                    hdgDeg.format("%03d") + "°",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Elevation display with a simple mountain glyph
    function _drawElevation(dc as Graphics.Dc, cx as Number, topY as Number,
                             accent as Number, dim as Number) as Void {
        // Altitude value
        var altFt = 0;
        if (_altM != null) {
            altFt = (_altM * 3.28084).toNumber();
        } else {
            altFt = 2400; // La Crescenta default ~2400 ft
        }

        var altStr  = altFt.format("%d");
        var unitStr = "ft";

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, topY, Graphics.FONT_NUMBER_MILD, altStr,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, topY + 28, Graphics.FONT_XTINY, unitStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Simple mountain glyph (3 triangular lines)
        var gY = topY + 42;
        var gW = 28;
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        // Left peak
        dc.drawLine(cx - gW/2, gY,     cx - gW/6, gY - 10);
        dc.drawLine(cx - gW/6, gY - 10, cx,        gY - 6);
        // Right peak (taller)
        dc.drawLine(cx,        gY - 6,  cx + gW/5, gY - 14);
        dc.drawLine(cx + gW/5, gY - 14, cx + gW/2, gY);
        // Base line
        dc.drawLine(cx - gW/2, gY, cx + gW/2, gY);
    }

    function _estimateUtcOffset(unixNow as Number, localInfo as Gregorian.Info) as Float {
        var utcHour   = ((unixNow % 86400) / 3600).toNumber();
        var localHour = localInfo.hour;
        var diff = localHour - utcHour;
        if (diff > 12)  { diff -= 24; }
        if (diff < -12) { diff += 24; }
        return diff.toFloat();
    }

    function _epochToLocalHHMM(epochUnix as Number) as String {
        var sysTime  = System.getClockTime();
        var localSec = epochUnix + sysTime.timeZoneOffset;
        var hh = ((localSec % 86400) / 3600).toNumber();
        var mm = ((localSec % 3600)  / 60).toNumber();
        if (hh < 0) { hh += 24; }
        if (mm < 0) { mm += 60; }
        return Lang.format("$1$:$2$", [hh.format("%02d"), mm.format("%02d")]);
    }

    function _drawBattery(dc as Graphics.Dc, cx as Number, y as Number,
                          accent as Number) as Void {
        var stats = System.getSystemStats();
        var pct   = stats.battery;
        var color = (pct < 20) ? Graphics.COLOR_RED
                  : (pct < 50) ? 0xFFAA00
                  : accent;
        var dotW  = ((pct / 100.0) * 60).toNumber();
        dc.setColor(0x2A2A2A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - 30, y - 3, 60, 6, 3);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (dotW > 0) { dc.fillRoundedRectangle(cx - 30, y - 3, dotW, 6, 3); }
    }

    function onHide()       as Void {}
    function onShow()       as Void {}
    function onEnterSleep() as Void { WatchUi.requestUpdate(); }
    function onExitSleep()  as Void { WatchUi.requestUpdate(); }
}
