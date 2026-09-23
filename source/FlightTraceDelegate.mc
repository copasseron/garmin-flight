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
}
