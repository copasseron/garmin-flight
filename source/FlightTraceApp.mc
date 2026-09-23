using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.Application;
using Toybox.Position;
using Toybox.Time;
using Toybox.WatchUi;

class FlightTraceApp extends Application.AppBase {
    var mSession = null;
    var mPositionInfo = null;
    var mLastAltitude = null;
    var mLastAltitudeMoment = null;
    var mVerticalSpeedMps = null;
    var mStartMoment = null;
    var mStatus = "READY";
    var mView = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        enablePositioning();
    }

    function onStop(state) {
        // Do not stop the FIT session here. Connect IQ can call onStop when
        // the app is suspended, and only the explicit Stop action should end
        // a flight. Position callbacks are managed by the system across the
        // inactive/active transition.
    }

    function getInitialView() {
        mView = new FlightTraceView(self);
        return [mView, new FlightTraceDelegate(self)];
    }

    function enablePositioning() {
        var options = {
            :acquisitionType => Position.LOCATION_CONTINUOUS
        };

        // Aviation positioning mode is available from API 3.2.0 and is
        // appropriate for flights that may exceed normal fitness altitudes.
        if (Position has :POSITIONING_MODE_AVIATION) {
            options[:mode] = Position.POSITIONING_MODE_AVIATION;
        }

        Position.enableLocationEvents(options, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (info.altitude != null && info.when != null &&
            mLastAltitude != null && mLastAltitudeMoment != null) {
            var seconds = info.when.subtract(mLastAltitudeMoment).value();
            if (seconds > 0 && seconds <= 30) {
                mVerticalSpeedMps = (info.altitude - mLastAltitude) / seconds;
            }
        }

        if (info.altitude != null) {
            mLastAltitude = info.altitude;
        }
        if (info.when != null) {
            mLastAltitudeMoment = info.when;
        }

        mPositionInfo = info;
        WatchUi.requestUpdate();
    }

    function toggleRecording() {
        if (isRecording()) {
            stopRecording();
        } else {
            startRecording();
        }
        WatchUi.requestUpdate();
    }

    function startRecording() {
        if (isRecording()) {
            mStatus = "ALREADY RECORDING";
            return false;
        }

        if (!(Toybox has :ActivityRecording)) {
            mStatus = "UNSUPPORTED";
            return false;
        }

        try {
            mSession = ActivityRecording.createSession({
                :name => "Flight Trace",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });

            if (!mSession.start()) {
                mSession = null;
                mStatus = "START FAILED";
                return false;
            }

            mStartMoment = Time.now();
            mVerticalSpeedMps = null;
            mStatus = "RECORDING";
            return true;
        } catch (exception) {
            mSession = null;
            mStartMoment = null;
            mStatus = "START FAILED";
            return false;
        }
    }

    function stopRecording() {
        if (!isRecording()) {
            mStatus = "NOT RECORDING";
            return false;
        }

        try {
            mSession.stop();
            mSession.save();
            mSession = null;
            mStartMoment = null;
            mStatus = "SAVED - SYNC GARMIN CONNECT";
            return true;
        } catch (exception) {
            // Keep the session reference available so the user can retry
            // rather than silently losing the recording.
            mStatus = "SAVE FAILED";
            return false;
        }
    }

    function isRecording() {
        return mSession != null && mSession.isRecording();
    }

    function getPositionInfo() {
        return mPositionInfo;
    }

    function getVerticalSpeedMps() {
        return mVerticalSpeedMps;
    }

    function getElapsedSeconds() {
        if (mStartMoment == null) {
            return 0;
        }

        return Time.now().subtract(mStartMoment).value();
    }

    function getStatus() {
        if (isRecording()) {
            if (mPositionInfo == null ||
                mPositionInfo.accuracy == Position.QUALITY_NOT_AVAILABLE) {
                return "RECORDING - NO GPS";
            }
            return "RECORDING";
        }

        return mStatus;
    }
}
