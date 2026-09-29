using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.Application;
using Toybox.Attention;
using Toybox.Math;
using Toybox.Position;
using Toybox.Time;
using Toybox.Timer;
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
    var mAirspaces = null;
    var mCurrentAirspace = null;
    var mPage = 0;
    var mPositionTimer;

    function initialize() {
        AppBase.initialize();
        mAirports = FranceAirports.getAll();
        mAirspaces = FranceAirspaces.getAll();
        mPositionTimer = new Timer.Timer();
    }

    function onStart(state) {
        mPage = 0;
        enablePositioning();
        mPositionTimer.start(method(:pollPosition), 1000, true);
        pollPosition();
    }

    function onStop(state) {
        mPositionTimer.stop();
        // Do not stop the FIT session here. Connect IQ can call onStop when
        // the app is suspended, and only the explicit Stop action should end
        // a flight. Position callbacks are managed by the system across the
        // inactive/active transition.
    }

    function pollPosition() as Void {
        var info = Position.getInfo();
        if (info != null) {
            onPosition(info);
        }
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
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
            updateCurrentAirspace(info.position, info.altitude);
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
                :bearingDegrees => closestBearing,
                :radio => closest[4],
                :runways => closest[5],
                :category => closest[6]
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
                :sport => Activity.SPORT_FLYING,
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
            playRecordingFeedback(true);
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
            mStatus = "SAVED - SYNC";
            playRecordingFeedback(false);
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

    function getCurrentAirspace() {
        return mCurrentAirspace;
    }

    function updateCurrentAirspace(location as Position.Location, altitudeMeters) as Void {
        var coordinates = location.toDegrees();
        var latitude = coordinates[0];
        var longitude = coordinates[1];
        var candidates = [];
        var altitudeFeet = altitudeMeters == null ? null : altitudeMeters * 3.28084;
        var altitudeRequired = false;

        for (var i = 0; i < mAirspaces.size(); i++) {
            var zone = mAirspaces[i];
            var bbox = zone[8];
            if (latitude < bbox[0] || latitude > bbox[1] ||
                longitude < bbox[2] || longitude > bbox[3]) {
                continue;
            }
            if (!pointInPolygon(latitude, longitude, zone[9])) {
                continue;
            }
            var vertical = verticalStatus(zone, altitudeFeet);
            if (vertical == 1) {
                altitudeRequired = true;
                continue;
            }
            if (vertical != 0) {
                continue;
            }
            candidates.add(zone);
        }

        if (candidates.size() == 0) {
            if (altitudeRequired) {
                mCurrentAirspace = {:status => "ALTITUDE REQUIRED"};
            } else {
                mCurrentAirspace = {:status => "NO ACTIVE AIRSPACE"};
            }
            return;
        }

        var selected = candidates[0];
        var selectedScore = airspaceRestrictionScore(selected);
        for (var j = 1; j < candidates.size(); j++) {
            var score = airspaceRestrictionScore(candidates[j]);
            if (score > selectedScore) {
                selected = candidates[j];
                selectedScore = score;
            }
        }

        mCurrentAirspace = {
            :status => "ACTIVE",
            :zone => selected,
            :overlapCount => candidates.size()
        };
    }

    // Returns 0 when the zone contains the altitude, 1 when an altitude is
    // required to decide, and 2 when the altitude is outside the zone.
    function verticalStatus(zone, altitudeFeet) {
        var floor = zone[3];
        var ceiling = zone[5];
        var floorReference = zone[4];
        var ceilingReference = zone[6];
        var isSurfaceFloor = floorReference != null && floorReference.equals("SFC");
        var isAboveGroundFloor = floorReference != null && floorReference.equals("AGL");
        var isAboveGroundCeiling = ceilingReference != null && ceilingReference.equals("AGL");
        if (isAboveGroundFloor || isAboveGroundCeiling) {
            return 1;
        }
        if (altitudeFeet == null &&
            (!isSurfaceFloor || isAboveGroundCeiling ||
             floor == null || ceiling == null)) {
            return 1;
        }
        if (altitudeFeet == null) {
            return 1;
        }
        if (floor != null && !isSurfaceFloor && altitudeFeet < floor) {
            return 2;
        }
        if (ceiling != null && altitudeFeet > ceiling) {
            return 2;
        }
        return 0;
    }

    function scheduleIsActive(schedule) {
        if (schedule == null || schedule == "" || schedule.equals("H24") ||
            schedule.equals("ACTIVE")) {
            return true;
        }
        // The generator keeps the original schedule text. H24 and empty
        // schedules are the only universally decidable forms in the watch
        // runtime; other schedules are shown as published but conservatively
        // treated as active until the schedule evaluator is extended.
        return true;
    }

    function pointInPolygon(latitude, longitude, polygon) {
        var inside = false;
        var pointCount = polygon.size() / 2;
        var previous = pointCount - 1;
        for (var i = 0; i < pointCount; i++) {
            var currentLat = polygon[i * 2];
            var currentLon = polygon[i * 2 + 1];
            var previousLat = polygon[previous * 2];
            var previousLon = polygon[previous * 2 + 1];
            var intersects = ((currentLat > latitude) != (previousLat > latitude)) &&
                (longitude < (previousLon - currentLon) * (latitude - currentLat) /
                (previousLat - currentLat) + currentLon);
            if (intersects) {
                inside = !inside;
            }
            previous = i;
        }
        return inside;
    }

    function airspaceRestrictionScore(zone) {
        var type = zone[1].toUpper();
        if (type.equals("P")) {
            return 500;
        }
        if (type.equals("R")) {
            return 450;
        }
        if (type.equals("D")) {
            return 400;
        }
        if (type.equals("CTR") || type.equals("TMA") || type.equals("CTA")) {
            return 300;
        }
        if (type.equals("RMZ") || type.equals("TMZ")) {
            return 200;
        }
        return 100;
    }

    function showFlightPage() {
        mPage = 0;
        WatchUi.requestUpdate();
    }

    function showAirportPage() {
        mPage = 1;
        WatchUi.requestUpdate();
    }

    function showAirspacePage() {
        mPage = 2;
        WatchUi.requestUpdate();
    }

    function showNextPage() {
        mPage = (mPage + 1) % 3;
        WatchUi.requestUpdate();
    }

    function showPreviousPage() {
        mPage = (mPage + 2) % 3;
        WatchUi.requestUpdate();
    }

    function getPage() {
        return mPage;
    }

    function getMagneticDeclinationDegrees() {
        var value = getProperty("magnetic_declination");
        if (value == null) {
            return 0.0;
        }
        return value;
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

    function playRecordingFeedback(started) {
        if (Attention has :playTone) {
            if (started) {
                Attention.playTone(Attention.TONE_START);
            } else {
                Attention.playTone(Attention.TONE_STOP);
            }
        }

        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 250)
            ]);
        }
    }
}
