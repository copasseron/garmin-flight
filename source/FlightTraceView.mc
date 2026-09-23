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

        drawCentered(dc, "FLIGHT TRACE", 8, Graphics.FONT_SMALL, Graphics.COLOR_LT_GRAY);
        drawCentered(dc, mApp.getStatus(), 34, Graphics.FONT_SMALL, statusColor());

        drawCentered(dc, altitudeText(info), 70, Graphics.FONT_LARGE, Graphics.COLOR_WHITE);
        drawCentered(dc, "ALTITUDE", 118, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY);

        drawMetric(dc, "GROUND SPEED", speedText(info), width / 4, 158);
        drawMetric(dc, "TRACK", headingText(info), (width * 3) / 4, 158);
        drawMetric(dc, "VERTICAL SPEED", verticalSpeedText(), width / 4, 232);
        drawMetric(dc, "ELAPSED", elapsedText(), (width * 3) / 4, 232);

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
