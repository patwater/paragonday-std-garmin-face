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

    // Cached solar data (refreshed once per day)
    var _sunrise  as Number? = null;
    var _sunset   as Number? = null;
    var _firstLight as Number? = null;   // civil dawn
    var _lastLight  as Number? = null;   // civil dusk
    var _noon       as Number? = null;   // solar noon
    var _lastDay  as Number  = -1;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {}

    function onUpdate(dc as Graphics.Dc) as Void {
        var now     = Time.now();
        var nowSecs = now.value();
        var unixNow = nowSecs; // Time.now() is already Unix epoch

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
            }
            var utcOffset = _estimateUtcOffset(unixNow, info);
            var solar     = SunCalc.compute(_lat, _lng, year, month, day, utcOffset);
            _sunrise = solar[:sunrise];
            _sunset  = solar[:sunset];
            _firstLight = solar[:firstLight];
            _lastLight  = solar[:lastLight];
            _noon       = solar[:solarNoon];
            _lastDay = day;
        }

        var cx = dc.getWidth()  / 2;
        var cy = dc.getHeight() / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var isDay = (_sunrise != null && _sunset != null)
                    ? (unixNow >= _sunrise && unixNow < _sunset)
                    : (info.hour >= 6 && info.hour < 20);

        var accentColor   = isDay ? 0xC8922A : 0x7BA3C8;
        var dimColor      = 0x888888;
        var twilightColor = 0xE05A00;   // deep orange: first light→sunrise, sunset→last light
        var ringColor     = 0xFFFFFF;   // white base
        var dotColor      = 0x2ECC71;   // green sun dot

        // ── 1. Horizon ring ──────────────────────────────────────────────
        // A 24 h sun dial around the bezel: solar noon at the top, the sun
        // moves clockwise, night runs along the bottom. 360° = 86400 s.
        var ringR = 112;
        dc.setPenWidth(4);
        dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, ringR);

        var primSign = "";
        var primTime = "--:--";
        var primLbl  = "";
        var secSign  = "";
        var secTime  = "--:--";
        var secLbl   = "";
        var dotDeg;                     // clockwise degrees from 12 o'clock
        if (_sunrise != null && _sunset != null) {
            var ht = SunCalc.horizonTime(unixNow, _sunrise, _sunset);
            var p = _splitLabel(ht[:primaryLine]);
            var q = _splitLabel(ht[:secondLine]);
            primSign = p[0]; primTime = p[1]; primLbl = p[2];
            secSign  = q[0]; secTime  = q[1]; secLbl  = q[2];
        }
        if (_noon != null) {
            // Orientation is always solar noon (true transit), never clock noon.
            if (_sunrise != null && _sunset != null) {
                dc.setPenWidth(10);   // thicker than the white ring
                dc.setColor(twilightColor, Graphics.COLOR_TRANSPARENT);
                if (_firstLight != null) {
                    _drawSlice(dc, cx, cy, ringR, _firstLight, _sunrise, _noon);
                }
                if (_lastLight != null) {
                    _drawSlice(dc, cx, cy, ringR, _sunset, _lastLight, _noon);
                }
            }
            dotDeg = _relDeg(unixNow, _noon);
        } else {
            dotDeg = 0.0;
        }
        dc.setPenWidth(1);

        var rad = dotDeg * Math.PI / 180.0;
        var dx  = cx + (ringR * Math.sin(rad)).toNumber();
        var dy  = cy - (ringR * Math.cos(rad)).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, 9);
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, 7);

        // ── 2. Sunrise / Sunset, then first light / last light ──────────
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 8, 28, Graphics.FONT_XTINY, "^" + _hhmm(_sunrise),
                    Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(cx + 8, 28, Graphics.FONT_XTINY, _hhmm(_sunset) + "v",
                    Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 8, 50, Graphics.FONT_XTINY, _hhmm(_firstLight),
                    Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(cx + 8, 50, Graphics.FONT_XTINY, _hhmm(_lastLight),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // ── 3. Horizon readings (label beside the number) ────────────────
        _drawReading(dc, cx, 84, primSign, primTime, primLbl,
                     Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_SMALL, accentColor);
        _drawReading(dc, cx, 142, secSign, secTime, secLbl,
                     Graphics.FONT_NUMBER_MILD, Graphics.FONT_XTINY, dimColor);

        // ── 4. Battery strip ─────────────────────────────────────────────
        _drawBattery(dc, cx, 206, accentColor);
    }

    // Degrees clockwise from 12 o'clock for an epoch time, relative to solar
    // noon, wrapped to [-180, 180).
    function _relDeg(t as Number, noon as Number) as Float {
        var d = (t - noon + 43200) % 86400;
        if (d < 0) { d += 86400; }
        return (d - 43200) / 240.0;
    }

    // Colored arc on the ring from time t1 to t2 (drawn clockwise).
    function _drawSlice(dc as Graphics.Dc, cx as Number, cy as Number, r as Number,
                        t1 as Number, t2 as Number, noon as Number) as Void {
        var g1 = 90.0 - _relDeg(t1, noon);   // Garmin angles: 0° = 3 o'clock, CCW+
        var g2 = 90.0 - _relDeg(t2, noon);
        while (g1 < 0.0) { g1 += 360.0; }
        while (g2 < 0.0) { g2 += 360.0; }
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, g1, g2);
    }

    // Draws "<sign><time> <label>" centred on cx. The sign and label use the
    // small font because the number fonts only reliably contain digits and ':'.
    function _drawReading(dc as Graphics.Dc, cx as Number, y as Number,
                          sign as String, time as String, label as String,
                          numFont, lblFont, color as Number) as Void {
        var gap = 4;
        var wS = dc.getTextWidthInPixels(sign,  lblFont);
        var wT = dc.getTextWidthInPixels(time,  numFont);
        var wL = dc.getTextWidthInPixels(label, lblFont);
        var hN = dc.getFontHeight(numFont);
        var hL = dc.getFontHeight(lblFont);
        var x  = cx - (wS + wT + gap + wL) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + (hN - hL) / 2, lblFont, sign, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + wS, y, numFont, time, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + wS + wT + gap, y + hN - hL - 4, lblFont, label,
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    function _hhmm(epoch as Number?) as String {
        return (epoch == null) ? "--:--" : _epochToLocalHHMM(epoch);
    }

    // Splits "-2:18 tilset" into ["-", "2:18", "tilset"]
    function _splitLabel(line as String) as Array<String> {
        var i = line.find(" ");
        if (i == null) { return ["", line, ""]; }
        return [line.substring(0, 1), line.substring(1, i),
                line.substring(i + 1, line.length())];
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
