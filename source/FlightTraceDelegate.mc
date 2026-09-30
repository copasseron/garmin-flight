using Toybox.System;
using Toybox.WatchUi;

class FlightTraceDelegate extends WatchUi.BehaviorDelegate {
    var mApp;

    function initialize(app) {
        BehaviorDelegate.initialize();
        mApp = app;
    }

    function onSelect() {
        mApp.toggleRecording();
        return true;
    }

    function onBack() {
        WatchUi.pushView(
            new WatchUi.Confirmation("LEAVE APP?"),
            new FlightTraceExitConfirmationDelegate(),
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

class FlightTraceExitConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response) {
        if (response == WatchUi.CONFIRM_YES) {
            System.exit();
        }
        return true;
    }
}
