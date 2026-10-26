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
        if (mApp.isWaitingForNearestCalibration()) {
            mApp.reopenAltitudeSourceSelection();
            return true;
        }

        if (!mApp.hasRecordingSession()) {
            System.exit();
            return true;
        }

        var menu = new WatchUi.Menu();
        menu.setTitle("FLIGHT");
        menu.addItem("SAVE & EXIT", :save);
        menu.addItem("RESUME LATER", :resume);
        menu.addItem("DISCARD", :discard);
        WatchUi.pushView(
            menu,
            new FlightTraceExitMenuDelegate(mApp),
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

class FlightTraceAltitudeSourceMenuDelegate extends WatchUi.MenuInputDelegate {
    var mApp;

    function initialize(app) {
        MenuInputDelegate.initialize();
        mApp = app;
    }

    function onMenuItem(item) {
        mApp.selectAltitudeSource(item);
    }
}

class FlightTraceManualAltitudeDelegate extends WatchUi.TextPickerDelegate {
    var mApp;

    function initialize(app) {
        TextPickerDelegate.initialize();
        mApp = app;
    }

    function onTextEntered(text, changed) {
        mApp.applyManualAltitudeText(text);
        return true;
    }

    function onCancel() {
        // Keep Garmin altitude if manual entry is cancelled.
        return true;
    }
}

class FlightTraceExitMenuDelegate extends WatchUi.MenuInputDelegate {
    var mApp;

    function initialize(app) {
        MenuInputDelegate.initialize();
        mApp = app;
    }

    function onMenuItem(item) {
        if (item == :save) {
            mApp.saveRecordingAndExit();
        } else if (item == :resume) {
            mApp.resumeLaterAndExit();
        } else if (item == :discard) {
            mApp.discardRecordingAndExit();
        }
    }
}
