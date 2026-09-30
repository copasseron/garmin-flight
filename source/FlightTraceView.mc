using Toybox.Graphics;
using Toybox.Math;
using Toybox.Position;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;
using Toybox.WatchUi;

class FlightTraceView extends WatchUi.View {
    var mApp;
    var mTimer;

    function initialize(app) {
        View.initialize();
        mApp = app;
        mTimer = new Timer.Timer();
    }

    function onShow() {
        // Configure touch only after the view is foregrounded. Calling this
        // from AppBase.onStart can throw on physical watches even though it
        // works in the simulator.
        try {
            WatchUi.configureTouchEvents({:enabled => false});
        } catch (exception) {
            // Button behavior remains available if a device rejects the
            // touch configuration for its current foreground state.
        }
        mTimer.start(method(:onTimer), 1000, true);
    }

    function onHide() {
        mTimer.stop();
    }

    function onTimer() {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (mApp.getPage() == 1) {
            drawAirportPage(dc);
        } else if (mApp.getPage() == 2) {
            drawAirspacePage(dc);
        } else {
            drawFlightPage(dc);
        }
    }

    function drawFlightPage(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var leftX = width / 4;
        var rightX = (width * 3) / 4;
        var topLine = (height * 24) / 100;
        var middleLine = (height * 49) / 100;
        var bottomLine = (height * 70) / 100;
        var info = mApp.getPositionInfo();

        drawCentered(dc, utcText() + " UTC", (height * 4) / 100,
            Graphics.FONT_LARGE, Graphics.COLOR_WHITE);
        drawCentered(dc, mApp.getStatus(), (height * 17) / 100,
            Graphics.FONT_XTINY, statusColor());

        drawGridMetric(dc, "ALTITUDE FT", altitudeValueText(info),
            leftX, topLine + 12, topLine + 36);
        drawGridMetric(dc, "SPEED KT", speedValueText(info),
            rightX, topLine + 12, topLine + 36);
        drawGridMetric(dc, "TRACK MAG", magneticHeadingText(info),
            leftX, middleLine + 12, middleLine + 36);
        var verticalSpeedLabel = width > 430 ? "VERT SPD FPM" : "VERT SPEED FPM";
        drawGridMetric(dc, verticalSpeedLabel, verticalSpeedValueText(),
            rightX, middleLine + 12, middleLine + 36);

        // Draw the grid after the field contents so the boundary lines stay
        // continuous instead of being clipped by text background rectangles.
        // The lines are on field boundaries and do not cross the glyphs.
        drawGridLine(dc, (width * 13) / 100, topLine,
            (width * 87) / 100, topLine);
        drawGridLine(dc, (width * 13) / 100, middleLine,
            (width * 87) / 100, middleLine);
        drawGridLine(dc, (width * 13) / 100, bottomLine,
            (width * 87) / 100, bottomLine);
        drawGridLine(dc, centerX, topLine, centerX, bottomLine);

        drawCentered(dc, "TIME " + elapsedText(), (height * 71) / 100,
            Graphics.FONT_SMALL, Graphics.COLOR_WHITE);
        drawCentered(dc, gpsStatusText(info), (height * 83) / 100,
            Graphics.FONT_XTINY, gpsStatusColor(info));
        drawStartAction(dc, height, 90);
    }

    function drawAirportPage(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var centerY = height / 2;
        var info = mApp.getPositionInfo();
        var airport = mApp.getNearestAirport();

        if (airport == null) {
            drawCentered(dc, "WAITING FOR GPS", (height * 48) / 100,
                Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE);
            drawCentered(dc, "NO AIRPORT FIX YET", (height * 58) / 100,
                Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY);
        } else {
            var radius = (width / 2) - 2;
            drawAirportInfoLayout(dc, width, height, airport);
            // The data is the background layer. The compass card and its
            // graduations have visual priority, followed by the ADF pointer.
            drawCompass(dc, centerX, centerY, radius, info);

            // Draw the ADF pointer last so it remains visible over the card
            // and the airport data, without letting its shaft cover the text.
            var heading = magneticHeadingDegrees(info);
            if (heading == null) {
                heading = 0;
            }
            var targetMagnetic = normalizeDegrees(
                airport[:bearingDegrees] - mApp.getMagneticDeclinationDegrees());
            var relativeTarget = normalizeDegrees(targetMagnetic - heading);
            drawAdfPointer(dc, centerX, centerY, radius, relativeTarget);
        }
    }

    function drawAirspacePage(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var current = mApp.getCurrentAirspace();

        drawCenteredSafe(dc, "AIRSPACE", (height * 7) / 100,
            Graphics.FONT_SMALL, Graphics.COLOR_WHITE, (width * 70) / 100);

        if (current == null) {
            drawCenteredSafe(dc, "WAITING FOR GPS", (height * 43) / 100,
                Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE, (width * 88) / 100);
            return;
        }

        var status = current[:status];
        if (!status.equals("ACTIVE")) {
            drawCenteredSafe(dc, status, (height * 45) / 100,
                Graphics.FONT_SMALL, status.equals("ALTITUDE REQUIRED") ?
                Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY,
                (width * 88) / 100);
            drawCenteredSafe(dc, "GPS POSITION OK", (height * 56) / 100,
                Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, (width * 78) / 100);
            drawAiracFooter(dc, width, height);
            return;
        }

        var zone = current[:zone];
        var frequencies = zone[7];
        drawCenteredSafe(dc, zone[0], (height * 17) / 100,
            Graphics.FONT_LARGE, Graphics.COLOR_WHITE, (width * 72) / 100);
        drawCenteredSafe(dc, zone[1] +
            (zone[2].length() > 0 ? "  CLASS " + zone[2] : ""),
            (height * 28) / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY,
            (width * 82) / 100);

        if (frequencies.size() == 0) {
            drawCenteredSafe(dc, "NO FREQUENCY PUBLISHED", (height * 44) / 100,
                Graphics.FONT_XTINY, Graphics.COLOR_YELLOW, (width * 86) / 100);
        } else {
            drawAirspaceFrequencyRow(dc, frequencies, 0, width, (height * 39) / 100);
            drawAirspaceFrequencyRow(dc, frequencies, 1, width, (height * 49) / 100);
        }

        var floorText = altitudeLimitText(zone[3], zone[4]);
        var ceilingText = altitudeLimitText(zone[5], zone[6]);
        drawCenteredSafe(dc, floorText + " - " + ceilingText,
            (height * 62) / 100, Graphics.FONT_SMALL, Graphics.COLOR_WHITE,
            (width * 86) / 100);
        drawCenteredSafe(dc, status, (height * 72) / 100,
            Graphics.FONT_XTINY, Graphics.COLOR_GREEN, (width * 70) / 100);
        if (current[:overlapCount] > 1) {
            drawCenteredSafe(dc, "+" + (current[:overlapCount] - 1).format("%d") + " OVERLAP",
                (height * 80) / 100, Graphics.FONT_XTINY, Graphics.COLOR_YELLOW,
                (width * 70) / 100);
        }
        drawAiracFooter(dc, width, height);
    }

    function drawAirspaceFrequencyRow(dc, frequencies, index, width, y) {
        if (frequencies.size() <= index) {
            return;
        }
        var item = frequencies[index];
        var label = item[0];
        if (item[1].length() > 0) {
            label += " " + item[1];
        }
        drawCenteredSafe(dc, label, y, Graphics.FONT_SMALL, Graphics.COLOR_YELLOW,
            (width * 78) / 100);
        if (index == 1 && frequencies.size() > 2) {
            drawCenteredSafe(dc, "+" + (frequencies.size() - 2).format("%d") + " FREQ",
                y + 15, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY,
                (width * 70) / 100);
        }
    }

    function altitudeLimitText(value, reference) {
        if (value == null) {
            return "--";
        }
        if (reference.equals("SFC")) {
            return "SFC";
        }
        if (reference.equals("FL")) {
            return "FL" + (value / 100.0).format("%03.0f");
        }
        return value.format("%0.0f") + " FT";
    }

    function drawAiracFooter(dc, width, height) {
        drawCenteredSafe(dc, "AIRAC " + FranceAirspaces.getAiracLabel(),
            (height * 91) / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY,
            (width * 75) / 100);
    }

    function drawAirportInfoLayout(dc, width, height, airport) {
        var centerX = width / 2;
        var centerY = height / 2;
        var slotWidth = (width * 52) / 100;
        var slotHeight = (height * 15) / 100;
        var leftX = (width * 24) / 100;
        var rightX = (width * 76) / 100;
        var topY = (height * 26) / 100;
        var bottomY = (height * 69) / 100;
        var slotTextWidth = slotWidth - 4;
        var lowerTextWidth = (width * 82) / 100;

        // Use the four quadrants and keep the ADF center unobstructed.
        drawAirportSlot(dc, leftX, topY, slotWidth, slotHeight);
        drawAirportSlot(dc, rightX, topY, slotWidth, slotHeight);

        var categoryColor = Graphics.COLOR_LT_GRAY;
        if (airport[:category].equals("CIVILIAN")) {
            categoryColor = Graphics.COLOR_GREEN;
        } else if (airport[:category].equals("MILITARY")) {
            categoryColor = Graphics.COLOR_RED;
        }
        drawCenteredSafeAt(dc, airport[:category], leftX, topY - 7,
            Graphics.FONT_XTINY, categoryColor, slotTextWidth);
        drawCenteredSafeAt(dc, airport[:radio], rightX, topY - 7,
            Graphics.FONT_XTINY, Graphics.COLOR_YELLOW, slotTextWidth);

        drawAirportSlot(dc, centerX, centerY, (width * 34) / 100,
            (height * 19) / 100);
        drawCenteredSafeAt(dc,
            airportShortName(airport[:ident], airport[:name]), centerX,
            centerY - 57, Graphics.FONT_SMALL, Graphics.COLOR_LT_GRAY,
            (width * 76) / 100);
        // Keep all four ICAO letters visible on the 260px and smaller
        // Forerunner screens; the large font used by the AMOLED watches does
        // not fit those round displays.
        var identFont = Graphics.FONT_LARGE;
        var identWidth = (width * 42) / 100;
        if (width < 300) {
            identFont = width < 230 ? Graphics.FONT_SMALL : Graphics.FONT_MEDIUM;
            identWidth = (width * 48) / 100;
        }
        drawCenteredSafeAt(dc, airport[:ident], centerX, centerY - 25,
            identFont, Graphics.COLOR_WHITE, identWidth);

        var runwayLabel = "RWY " + airport[:runways];
        if (airport[:runways] == "WATER") {
            runwayLabel = "WATER BASE";
        }
        drawAirportSlot(dc, centerX, bottomY, lowerTextWidth,
            (height * 26) / 100);
        drawCenteredSafeAt(dc,
            distanceText(airport[:distanceMeters]) + " | " +
            magneticBearingText(airport[:bearingDegrees]),
            centerX, bottomY - 19, Graphics.FONT_SMALL, Graphics.COLOR_WHITE,
            lowerTextWidth - 8);
        drawCenteredSafeAt(dc, runwayLabel, centerX, bottomY + 27,
            Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, lowerTextWidth - 8);
    }

    function drawAirportSlot(dc, centerX, centerY, slotWidth, slotHeight) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(centerX - (slotWidth / 2), centerY - (slotHeight / 2),
            slotWidth, slotHeight);
    }

    function drawCompass(dc, centerX, centerY, radius, info) {
        var heading = magneticHeadingDegrees(info);
        if (heading == null) {
            heading = 0;
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        dc.drawCircle(centerX, centerY, radius);
        dc.drawCircle(centerX, centerY, radius - 3);
        dc.setPenWidth(1);

        // Rotate the compass card so the current magnetic heading is always at 12 o'clock.
        for (var bearing = 0; bearing < 360; bearing += 30) {
            var relativeBearing = normalizeDegrees(bearing - heading);
            var radians = (relativeBearing - 90) * Math.PI / 180.0;
            var outerRadius = radius - 5;
            var innerRadius = radius - 12;
            if ((bearing % 90) == 0) {
                innerRadius = radius - 24;
                dc.setPenWidth(3);
            } else {
                dc.setPenWidth(1);
            }
            var outerX = centerX + Math.cos(radians) * outerRadius;
            var outerY = centerY + Math.sin(radians) * outerRadius;
            var innerX = centerX + Math.cos(radians) * innerRadius;
            var innerY = centerY + Math.sin(radians) * innerRadius;
            dc.drawLine(innerX, innerY, outerX, outerY);
        }
        dc.setPenWidth(1);

        drawCompassCardLabel(dc, "N", 0, heading, centerX, centerY, radius);
        drawCompassCardLabel(dc, "E", 90, heading, centerX, centerY, radius);
        drawCompassCardLabel(dc, "S", 180, heading, centerX, centerY, radius);
        drawCompassCardLabel(dc, "W", 270, heading, centerX, centerY, radius);
    }

    function drawCompassLabel(dc, text, x, y) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var font = Graphics.FONT_XTINY;
        var textHeight = dc.getFontHeight(font);
        dc.drawText(x, y - (textHeight / 2), font, text,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawCompassCardLabel(dc, text, bearing, heading, centerX, centerY, radius) {
        var relativeBearing = normalizeDegrees(bearing - heading);
        var radians = (relativeBearing - 90) * Math.PI / 180.0;
        var labelRadius = radius - 28;
        var x = centerX + Math.cos(radians) * labelRadius;
        var y = centerY + Math.sin(radians) * labelRadius;
        drawCompassLabel(dc, text, x, y);
    }

    function drawAdfPointer(dc, centerX, centerY, radius, relativeBearing) {
        var radians = (relativeBearing - 90) * Math.PI / 180.0;
        // Extend the pointer to the inside edge of the compass.
        var tipRadius = radius - 8;
        var tailRadius = (radius * 58) / 100;
        var tipX = centerX + Math.cos(radians) * tipRadius;
        var tipY = centerY + Math.sin(radians) * tipRadius;
        var startX = centerX + Math.cos(radians) * tailRadius;
        var startY = centerY + Math.sin(radians) * tailRadius;
        var wingRadians = radians + Math.PI / 2;
        var wingRadius = 15;
        var wingX1 = tipX - Math.cos(radians) * 18 + Math.cos(wingRadians) * wingRadius;
        var wingY1 = tipY - Math.sin(radians) * 18 + Math.sin(wingRadians) * wingRadius;
        var wingX2 = tipX - Math.cos(radians) * 18 - Math.cos(wingRadians) * wingRadius;
        var wingY2 = tipY - Math.sin(radians) * 18 - Math.sin(wingRadians) * wingRadius;

        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_BLACK);
        dc.setPenWidth(3);
        dc.drawLine(startX, startY, tipX, tipY);
        dc.drawLine(wingX1, wingY1, tipX, tipY);
        dc.drawLine(wingX2, wingY2, tipX, tipY);
        dc.setPenWidth(1);
    }

    function drawGridLine(dc, x1, y1, x2, y2) {
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
        dc.drawLine(x1, y1, x2, y2);
    }

    function drawCentered(dc, text, y, font, color) {
        drawCenteredAt(dc, text, dc.getWidth() / 2, y, font, color);
    }

    function drawCenteredSafe(dc, text, y, font, color, maxWidth) {
        var fittedText = text;
        while (fittedText.length() > 1 &&
            dc.getTextWidthInPixels(fittedText, font) > maxWidth) {
            fittedText = fittedText.substring(0, fittedText.length() - 1);
        }
        drawCentered(dc, fittedText, y, font, color);
    }

    function drawCenteredSafeAt(dc, text, x, y, font, color, maxWidth) {
        var fittedText = text;
        while (fittedText.length() > 1 &&
            dc.getTextWidthInPixels(fittedText, font) > maxWidth) {
            fittedText = fittedText.substring(0, fittedText.length() - 1);
        }
        drawCenteredAt(dc, fittedText, x, y, font, color);
    }

    function drawCenteredAt(dc, text, x, y, font, color) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawGridMetric(dc, label, value, x, labelY, valueY) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(x, labelY, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(x, valueY, Graphics.FONT_MEDIUM, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function statusColor() {
        if (mApp.isRecording()) {
            return Graphics.COLOR_GREEN;
        }
        return Graphics.COLOR_YELLOW;
    }

    function actionColor() {
        if (mApp.isRecording()) {
            return Graphics.COLOR_RED;
        }
        return Graphics.COLOR_GREEN;
    }

    function drawStartAction(dc, height, yPercent) {
        if (!mApp.isRecording()) {
            drawCentered(dc, "START FLIGHT", (height * yPercent) / 100,
                Graphics.FONT_XTINY, actionColor());
        }
    }

    function gpsStatusText(info) {
        if (info == null || info.accuracy == null ||
            info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return "GPS SEARCH";
        }

        if (info.accuracy == Position.QUALITY_GOOD) {
            return "GPS 3D FIX";
        }

        if (info.accuracy == Position.QUALITY_USABLE) {
            return "GPS 3D OK";
        }

        if (info.accuracy == Position.QUALITY_POOR) {
            return "GPS 2D FIX";
        }

        if (info.accuracy == Position.QUALITY_LAST_KNOWN) {
            return "GPS LAST FIX";
        }

        return "GPS ON";
    }

    function gpsStatusColor(info) {
        if (info == null || info.accuracy == null ||
            info.accuracy == Position.QUALITY_NOT_AVAILABLE ||
            info.accuracy == Position.QUALITY_LAST_KNOWN ||
            info.accuracy == Position.QUALITY_POOR) {
            return Graphics.COLOR_YELLOW;
        }

        return Graphics.COLOR_GREEN;
    }

    function altitudeValueText(info) {
        if (info == null || info.altitude == null) {
            return "--";
        }
        return (info.altitude * 3.28084).format("%0.0f");
    }

    function speedValueText(info) {
        if (info == null || info.speed == null) {
            return "--";
        }
        return (info.speed * 1.94384).format("%0.0f");
    }

    function verticalSpeedValueText() {
        var verticalSpeed = mApp.getVerticalSpeedMps();
        if (verticalSpeed == null) {
            return "--";
        }
        return (verticalSpeed * 196.850394).format("%+0.0f");
    }

    function altitudeText(info) {
        return altitudeValueText(info) + " ft";
    }

    function speedText(info) {
        return speedValueText(info) + " kt";
    }

    function distanceText(meters) {
        return (meters / 1852.0).format("%0.1f") + " NM";
    }

    function magneticBearingText(degrees) {
        return normalizeDegrees(degrees - mApp.getMagneticDeclinationDegrees()).format("%03.0f") + "°";
    }

    function magneticHeadingDegrees(info) {
        if (info == null || info.heading == null) {
            return null;
        }
        var trueDegrees = info.heading * 57.2957795;
        return normalizeDegrees(trueDegrees - mApp.getMagneticDeclinationDegrees());
    }

    function magneticHeadingText(info) {
        var heading = magneticHeadingDegrees(info);
        if (heading == null) {
            return "---°";
        }
        return heading.format("%03.0f") + "°";
    }

    function normalizeDegrees(degrees) {
        while (degrees < 0) {
            degrees += 360;
        }
        while (degrees >= 360) {
            degrees -= 360;
        }
        return degrees;
    }

    function airportShortName(ident, name) {
        // Use the chart-style short callout instead of the long legal name.
        if (ident.equals("LFPZ")) {
            return "SAINT-CYR";
        }

        var shortName = name;
        var upperName = name.toUpper();
        var suffixes = [" AIRPORT", " AIRFIELD", " AERODROME", " AÉRODROME",
            " AIR BASE", " BASE"];
        for (var i = 0; i < suffixes.size(); i++) {
            var suffixIndex = upperName.find(suffixes[i]);
            if (suffixIndex != null) {
                shortName = name.substring(0, suffixIndex);
                break;
            }
        }

        var detailIndex = shortName.find(" (");
        if (detailIndex != null) {
            shortName = shortName.substring(0, detailIndex);
        }
        if (shortName.length() == 0) {
            shortName = name;
        }
        return shortName.toUpper();
    }

    function elapsedText() {
        var seconds = mApp.getElapsedSeconds();
        var hours = (seconds / 3600.0).format("%02.0f");
        var minutes = ((seconds % 3600) / 60.0).format("%02.0f");
        var remainder = (seconds % 60).format("%02.0f");
        return hours + ":" + minutes + ":" + remainder;
    }

    function utcText() {
        var info = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        return info.hour.format("%02.0f") + ":" + info.min.format("%02.0f");
    }
}
