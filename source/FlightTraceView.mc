using Toybox.Graphics;
using Toybox.Position;
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

        var width = dc.getWidth();
        var info = mApp.getPositionInfo();
        var airport = mApp.getNearestAirport();

        drawCentered(dc, "NEAREST AIRPORT", 8, Graphics.FONT_SMALL, Graphics.COLOR_LT_GRAY);
        drawCentered(dc, mApp.getStatus(), 34, Graphics.FONT_SMALL, statusColor());

        if (airport == null) {
            drawCentered(dc, "WAITING FOR GPS", 82, Graphics.FONT_LARGE, Graphics.COLOR_WHITE);
            drawCentered(dc, "AIRPORT DATA: FRANCE", 126, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY);
        } else {
            drawCentered(dc, airport[:ident], 70, Graphics.FONT_LARGE, Graphics.COLOR_WHITE);
            drawCentered(dc, airportName(airport[:name]), 112, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY);
            drawMetric(dc, "DISTANCE", distanceText(airport[:distanceMeters]), width / 4, 148);
            drawMetric(dc, "BEARING TRUE", bearingText(airport[:bearingDegrees]), (width * 3) / 4, 148);
        }

        drawMetric(dc, "ALTITUDE", altitudeText(info), width / 4, 230);
        drawMetric(dc, "GROUND SPEED", speedText(info), (width * 3) / 4, 230);

        var action = mApp.isRecording() ? "SELECT: STOP FLIGHT" : "SELECT: START FLIGHT";
        drawCentered(dc, action, 326, Graphics.FONT_SMALL, actionColor());
        drawCentered(dc, "GPS TRACE SAVES TO GARMIN CONNECT", 366, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY);
    }

    function drawCentered(dc, text, y, font, color) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawMetric(dc, label, value, x, y) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(x, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(x, y + 18, Graphics.FONT_MEDIUM, value, Graphics.TEXT_JUSTIFY_CENTER);
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

    function altitudeText(info) {
        if (info == null || info.altitude == null) {
            return "-- ft";
        }
        return (info.altitude * 3.28084).format("%0.0f") + " ft";
    }

    function speedText(info) {
        if (info == null || info.speed == null) {
            return "-- kt";
        }
        return (info.speed * 1.94384).format("%0.0f") + " kt";
    }

    function distanceText(meters) {
        return (meters / 1852.0).format("%0.1f") + " NM";
    }

    function bearingText(degrees) {
        return degrees.format("%03.0f") + "°T";
    }

    function airportName(name) {
        if (name.length() > 34) {
            return name.substring(0, 34);
        }
        return name;
    }

    function headingText(info) {
        if (info == null || info.heading == null) {
            return "---°";
        }

        var degrees = info.heading * 57.2957795;
        if (degrees < 0) {
            degrees += 360;
        }
        return degrees.format("%03.0f") + "°";
    }

    function verticalSpeedText() {
        var verticalSpeed = mApp.getVerticalSpeedMps();
        if (verticalSpeed == null) {
            return "-- fpm";
        }
        return (verticalSpeed * 196.850394).format("%+0.0f") + " fpm";
    }

    function elapsedText() {
        var seconds = mApp.getElapsedSeconds();
        var hours = (seconds / 3600.0).format("%02.0f");
        var minutes = ((seconds % 3600) / 60.0).format("%02.0f");
        var remainder = (seconds % 60).format("%02.0f");
        return hours + ":" + minutes + ":" + remainder;
    }
}
