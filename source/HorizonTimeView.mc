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
            _lastDay = day;
        }

        var cx = dc.getWidth() / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var isDay = (_sunrise != null && _sunset != null)
                    ? (unixNow >= _sunrise && unixNow < _sunset)
                    : (info.hour >= 6 && info.hour < 20);

        var accentColor = isDay ? 0xC8922A : 0x7BA3C8;
        var dimColor    = 0x888888;
        var mutedColor  = 0x3A3A3A;

        // ── 1. Date ──────────────────────────────────────────────────────
        var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        var monNames = ["Jan","Feb","Mar","Apr","May","Jun",
                        "Jul","Aug","Sep","Oct","Nov","Dec"];
        var dateStr  = Lang.format("$1$ $2$ $3$",
            [dayNames[info.day_of_week - 1], monNames[month - 1], day.format("%02d")]);
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 16, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ── 2. Arc progress bar ──────────────────────────────────────────
        var barH = 6;
        var barW = 150;
        var barX = cx - barW / 2;
        var barY = 46;

        dc.setColor(mutedColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, barW, barH, 3);

        var arcFill  = 0.5f;
        var primTime = "--:--";
        var primLbl  = "";
        var secTime  = "--:--";
        var secLbl   = "";
        if (_sunrise != null && _sunset != null) {
            var ht   = SunCalc.horizonTime(unixNow, _sunrise, _sunset);
            arcFill  = ht[:arcFill].toFloat();
            var p = _splitLabel(ht[:primaryLine]);
            var q = _splitLabel(ht[:secondLine]);
            primTime = p[0]; primLbl = p[1];
            secTime  = q[0]; secLbl  = q[1];
        } else {
            arcFill = (info.hour * 3600 + info.min * 60).toFloat() / 86400.0;
        }
        var fillW = (arcFill * barW).toNumber();
        if (fillW < 6)  { fillW = 6; }
        if (fillW > barW) { fillW = barW; }
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, fillW, barH, 3);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(barX + fillW, barY + barH / 2, 5);

        // ── 3. Sunrise / Sunset times ────────────────────────────────────
        var riseStr = "--:--";
        var setStr  = "--:--";
        if (_sunrise != null) { riseStr = _epochToLocalHHMM(_sunrise); }
        if (_sunset  != null) { setStr  = _epochToLocalHHMM(_sunset);  }
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(barX,        58, Graphics.FONT_XTINY, "^" + riseStr,
                    Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(barX + barW, 58, Graphics.FONT_XTINY, setStr + "v",
                    Graphics.TEXT_JUSTIFY_RIGHT);

        // ── 4. Horizon readings ──────────────────────────────────────────
        // Primary: countdown to next horizon event
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 84, Graphics.FONT_NUMBER_MEDIUM, primTime,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 130, Graphics.FONT_SMALL, primLbl,
                    Graphics.TEXT_JUSTIFY_CENTER);
        // Secondary: elapsed since last horizon event
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 158, Graphics.FONT_NUMBER_MILD, secTime,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 192, Graphics.FONT_XTINY, secLbl,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ── 5. Battery strip ─────────────────────────────────────────────
        _drawBattery(dc, cx, 226, accentColor);
    }

    // Splits "-2:18 tilset" into ["-2:18", "tilset"]
    function _splitLabel(line as String) as Array<String> {
        var i = line.find(" ");
        if (i == null) { return [line, ""]; }
        return [line.substring(0, i), line.substring(i + 1, line.length())];
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
