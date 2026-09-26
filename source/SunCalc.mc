// SunCalc.mc — Solar position and Horizon Time calculations
// Adapted for Garmin Connect IQ / MonkeyC
//
// Implements the Paragonday Systems Horizon Time standard.
// Time is expressed relative to the two daily horizon events:
//
//   DAYTIME  (sunrise → sunset)
//     +HH:MM pastrise   — elapsed time since sunrise
//     -HH:MM tilset     — countdown until sunset
//
//   NIGHTTIME (sunset → next sunrise)
//     +HH:MM pastset    — elapsed time since sunset
//     -HH:MM tilrise    — countdown until next sunrise
//
// The face shows the two readings simultaneously, e.g.:
//   -0:02 tilset  /  +12:02 pastrise

import Toybox.Math;
import Toybox.Lang;

class SunCalc {

    // -- Constants --
    static const RAD    = Math.PI / 180.0;
    static const DEG    = 180.0 / Math.PI;
    // Zenith for civil sunrise/sunset (centre of sun on horizon + refraction)
    static const ZENITH = 90.833;
    // Civil twilight: sun 6 degrees below the horizon (first light / last light)
    static const ZENITH_CIVIL = 96.0;

    // Returns a Dictionary with keys:
    //   :sunrise  — Unix epoch seconds (UTC) of today's sunrise, or null
    //   :sunset   — Unix epoch seconds (UTC) of today's sunset, or null
    //   :solarNoon — Unix epoch seconds (UTC) of solar noon
    static function compute(lat as Float, lng as Float,
                            year as Number, month as Number, day as Number,
                            utcOffsetHours as Float) as Dictionary {

        // Day of year
        var N1 = Math.floor(275.0 * month / 9.0).toNumber();
        var N2 = Math.floor((month + 9.0) / 12.0).toNumber();
        var N3 = (1 + Math.floor((year - 4 * Math.floor(year / 4.0) + 2.0) / 3.0)).toNumber();
        var N  = N1 - (N2 * N3) + day - 30;

        var lngHour = lng / 15.0;
        var tRise = N + ((6.0  - lngHour) / 24.0);
        var tSet  = N + ((18.0 - lngHour) / 24.0);

        var result = {};
        result[:sunrise]    = _eventEpoch(tRise, lat, lng, year, month, day, true,  ZENITH);
        result[:sunset]     = _eventEpoch(tSet,  lat, lng, year, month, day, false, ZENITH);
        result[:firstLight] = _eventEpoch(tRise, lat, lng, year, month, day, true,  ZENITH_CIVIL);
        result[:lastLight]  = _eventEpoch(tSet,  lat, lng, year, month, day, false, ZENITH_CIVIL);

        var sr = result[:sunrise];
        var ss = result[:sunset];
        var fl = result[:firstLight];
        var ll = result[:lastLight];
        // UTC wrap (western longitudes): keep firstLight < sunrise < sunset < lastLight
        if (sr != null && ss != null && ss < sr) { ss += 86400; result[:sunset] = ss; }
        if (fl != null && sr != null && fl > sr) { result[:firstLight] = fl - 86400; }
        if (ll != null && ss != null && ll < ss) { result[:lastLight]  = ll + 86400; }

        if (result[:sunrise] != null && result[:sunset] != null) {
            // sunrise + sunset would overflow a 32-bit Number
            result[:solarNoon] = result[:sunrise] + (result[:sunset] - result[:sunrise]) / 2;
        } else {
            result[:solarNoon] = null;
        }
        return result;
    }

    // Returns Unix epoch seconds for a solar event, or null for polar day/night.
    static function _eventEpoch(t as Float, lat as Float, lng as Float,
                                year as Number, month as Number, day as Number,
                                isRise as Boolean, zenith as Float) as Number or Null {

        var M = (0.9856 * t) - 3.289;

        var L = M + (1.916 * Math.sin(M * RAD)) + (0.020 * Math.sin(2.0 * M * RAD)) + 282.634;
        L = _mod360(L);

        var RA = Math.atan(0.91764 * Math.tan(L * RAD)) * DEG;
        RA = _mod360(RA);

        var Lquadrant  = Math.floor(L  / 90.0) * 90.0;
        var RAquadrant = Math.floor(RA / 90.0) * 90.0;
        RA = (RA + (Lquadrant - RAquadrant)) / 15.0;

        var sinDec = 0.39782 * Math.sin(L * RAD);
        var cosDec = Math.cos(Math.asin(sinDec));

        var cosH = (Math.cos(zenith * RAD) - (sinDec * Math.sin(lat * RAD)))
                   / (cosDec * Math.cos(lat * RAD));

        if (cosH > 1.0)  { return null; }
        if (cosH < -1.0) { return null; }

        var H = Math.acos(cosH) * DEG;
        if (isRise) { H = 360.0 - H; }
        H = H / 15.0;

        var T  = H + RA - (0.06571 * t) - 6.622;
        var UT = _mod24(T - (lng / 15.0));

        var epochSec = (_daysSinceEpoch(year, month, day) * 86400) + (UT * 3600.0).toNumber();
        return epochSec;
    }

    static function _daysSinceEpoch(year as Number, month as Number, day as Number) as Number {
        if (month <= 2) { year -= 1; month += 12; }
        var A  = (year / 100).toNumber();
        var B  = 2 - A + (A / 4).toNumber();
        var jd = ((365.25 * (year + 4716)).toNumber()
                 + (30.6001 * (month + 1)).toNumber()
                 + day + B - 1524).toNumber();
        return jd - 2440588;
    }

    static function _mod360(v as Float) as Float {
        while (v <   0.0) { v += 360.0; }
        while (v >= 360.0) { v -= 360.0; }
        return v;
    }

    static function _mod24(v as Float) as Float {
        while (v <   0.0) { v += 24.0; }
        while (v >= 24.0) { v -= 24.0; }
        return v;
    }

    // -----------------------------------------------------------------------
    // Paragonday Horizon Time
    // -----------------------------------------------------------------------
    // Returns a Dictionary:
    //   :phase       — :day or :night
    //   :primaryLine — e.g. "-0:02 tilset"  (the imminent event)
    //   :secondLine  — e.g. "+12:02 pastrise" (elapsed since last event)
    //   :arcFill     — 0.0–1.0, progress through the current arc (for the bar)
    //   :pastSecs    — seconds elapsed since the last horizon event
    //   :tilSecs     — seconds until the next horizon event
    //
    // nowEpoch, sunriseEpoch, sunsetEpoch are all Unix epoch seconds.

    static function horizonTime(nowEpoch as Number,
                                sunriseEpoch as Number,
                                sunsetEpoch as Number) as Dictionary {

        var phase;
        var pastSecs;
        var tilSecs;
        var pastLabel;
        var tilLabel;
        var arcFill;
        var arcStart;
        var arcEnd;

        if (nowEpoch >= sunriseEpoch && nowEpoch < sunsetEpoch) {
            // ── Daytime ──────────────────────────────────────────────
            phase    = :day;
            arcStart = sunriseEpoch;
            arcEnd   = sunsetEpoch;
            pastSecs = nowEpoch - sunriseEpoch;         // since sunrise
            tilSecs  = sunsetEpoch - nowEpoch;          // until sunset
            var span = (sunsetEpoch - sunriseEpoch).toFloat();
            arcFill  = pastSecs.toFloat() / span;
            pastLabel = "pastrise";
            tilLabel  = "tilset";
        } else if (nowEpoch < sunriseEpoch) {
            // ── Night: before sunrise (use yesterday's sunset = sunset - 86400) ──
            phase    = :night;
            var prevSunset = sunsetEpoch - 86400;
            arcStart = prevSunset;
            arcEnd   = sunriseEpoch;
            pastSecs = nowEpoch - prevSunset;           // since yesterday's sunset
            tilSecs  = sunriseEpoch - nowEpoch;         // until today's sunrise
            if (pastSecs < 0) { pastSecs = 0; }
            var span = (sunriseEpoch - prevSunset).toFloat();
            arcFill  = (span > 0) ? pastSecs.toFloat() / span : 0.0;
            pastLabel = "pastset";
            tilLabel  = "tilrise";
        } else {
            // ── Night: after sunset ───────────────────────────────────
            phase    = :night;
            var nextSunrise = sunriseEpoch + 86400;
            arcStart = sunsetEpoch;
            arcEnd   = nextSunrise;
            pastSecs = nowEpoch - sunsetEpoch;          // since today's sunset
            tilSecs  = nextSunrise - nowEpoch;          // until tomorrow's sunrise
            var span = (nextSunrise - sunsetEpoch).toFloat();
            arcFill  = (span > 0) ? pastSecs.toFloat() / span : 0.0;
            pastLabel = "pastset";
            tilLabel  = "tilrise";
        }

        if (arcFill < 0.0) { arcFill = 0.0; }
        if (arcFill > 1.0) { arcFill = 1.0; }

        return {
            :phase        => phase,
            :primaryLine  => _fmtTil(tilSecs,  tilLabel),
            :secondLine   => _fmtPast(pastSecs, pastLabel),
            :arcFill      => arcFill,
            :arcStart     => arcStart,
            :arcEnd       => arcEnd,
            :pastSecs     => pastSecs,
            :tilSecs      => tilSecs
        };
    }

    // "+HH:MM label" — elapsed since last event
    static function _fmtPast(secs as Number, label as String) as String {
        var h = secs / 3600;
        var m = (secs % 3600) / 60;
        return Lang.format("+$1$:$2$ $3$",
            [h.format("%d"), m.format("%02d"), label]);
    }

    // "-HH:MM label" — countdown to next event
    static function _fmtTil(secs as Number, label as String) as String {
        var h = secs / 3600;
        var m = (secs % 3600) / 60;
        return Lang.format("-$1$:$2$ $3$",
            [h.format("%d"), m.format("%02d"), label]);
    }
}
