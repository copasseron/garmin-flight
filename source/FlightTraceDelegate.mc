using Toybox.System;
using Toybox.WatchUi;

class FlightTraceDelegate extends WatchUi.BehaviorDelegate {
    var mApp;

    function initialize(app) {
        BehaviorDelegate.initialize();
        mApp = app;
    }

    function onSelect() {
        if (mApp.getPage() == 1 && !mApp.hasRecordingSession() &&
            mApp.canCalibrateNearestAirport()) {
            mApp.requestAltitudeCalibration();
        } else {
            mApp.toggleRecording();
        }
        return true;
    }

    function onBack() {
        WatchUi.pushView(
            new WatchUi.Confirmation("LEAVE APP?"),
            new FlightTraceExitConfirmationDelegate(mApp),
            WatchUi.SLIDE_IMMEDIATE
        );
        return true;
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();

        if (key == WatchUi.KEY_DOWN) {
            mApp.showNextPage();
            return true;
        }

        if (key == WatchUi.KEY_UP) {
            mApp.showPreviousPage();
            return true;
        }

        return true;
    }
}

class FlightTraceCalibrationConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    var mApp;

    function initialize(app) {
        ConfirmationDelegate.initialize();
        mApp = app;
    }

    function onResponse(response) {
        if (response == WatchUi.CONFIRM_YES) {
            mApp.applyAltitudeCalibration();
        }
        return true;
    }
}

class FlightTraceExitConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    var mApp;

    function initialize(app) {
        ConfirmationDelegate.initialize();
        mApp = app;
    }

    function onResponse(response) {
        if (response == WatchUi.CONFIRM_YES) {
            mApp.finishRecordingAndExit();
        }
        return true;
    }
}
