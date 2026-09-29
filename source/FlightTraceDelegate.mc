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

    function onTap(clickEvent) {
        mApp.toggleRecording();
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
