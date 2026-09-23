using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.Application;
using Toybox.Math;
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
    var mAirports = null;
    var mNearestAirport = null;

    function initialize() {
        AppBase.initialize();
        mAirports = FranceAirports.getAll();
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
        if (info.position != null) {
            updateNearestAirport(info.position);
        }
        WatchUi.requestUpdate();
    }

    function updateNearestAirport(location as Position.Location) as Void {
        var coordinates = location.toDegrees();
        var latitude = coordinates[0] * Math.PI / 180.0;
        var longitude = coordinates[1] * Math.PI / 180.0;
        var closest = null;
        var closestDistance = null;
        var closestBearing = null;

        for (var i = 0; i < mAirports.size(); i++) {
            var airport = mAirports[i];
            var airportLatitude = airport[2] * Math.PI / 180.0;
            var airportLongitude = airport[3] * Math.PI / 180.0;
            var deltaLatitude = airportLatitude - latitude;
            var deltaLongitude = airportLongitude - longitude;

            var haversine = Math.sin(deltaLatitude / 2.0) * Math.sin(deltaLatitude / 2.0) +
                Math.cos(latitude) * Math.cos(airportLatitude) *
                Math.sin(deltaLongitude / 2.0) * Math.sin(deltaLongitude / 2.0);
            var distance = 2.0 * 6371000.0 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1.0 - haversine));

            if (closestDistance == null || distance < closestDistance) {
                var y = Math.sin(deltaLongitude) * Math.cos(airportLatitude);
                var x = Math.cos(latitude) * Math.sin(airportLatitude) -
                    Math.sin(latitude) * Math.cos(airportLatitude) * Math.cos(deltaLongitude);
                var bearing = Math.atan2(y, x) * 180.0 / Math.PI;
                if (bearing < 0) {
                    bearing += 360.0;
                }

                closest = airport;
                closestDistance = distance;
                closestBearing = bearing;
            }
        }

        if (closest != null) {
            mNearestAirport = {
                :ident => closest[0],
                :name => closest[1],
                :distanceMeters => closestDistance,
                :bearingDegrees => closestBearing
            };
        }
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

    function getNearestAirport() {
        return mNearestAirport;
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
