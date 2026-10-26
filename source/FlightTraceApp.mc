using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.ActivityMonitor;
using Toybox.Application;
using Toybox.Attention;
using Toybox.Math;
using Toybox.Position;
using Toybox.Sensor;
using Toybox.Time;
using Toybox.Timer;
using Toybox.WatchUi;

class FlightTraceApp extends Application.AppBase {
    var mSession = null;
    var mPositionInfo = null;
    var mSensorInfo = null;
    var mActivityMonitorInfo = null;
    var mAltitudeCalibrationFeet = null;
    var mAltitudeCalibrationAirport = null;
    var mPendingManualAltitudeFeet = null;
    var mPendingNearestCalibration = false;
    var mAltitudeSourcePromptShown = false;
    var mLastAltitude = null;
    var mLastAltitudeMoment = null;
    var mVerticalSpeedMps = null;
    var mStartMoment = null;
    var mPausedMoment = null;
    var mPausedSeconds = 0;
    var mRecordingFeedbackUntil = null;
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
        enableHealthSensors();
        startPositionTracking();
    }

    function onStop(state) {
        mPositionTimer.stop();
        // Do not stop the FIT session here. Connect IQ can call onStop when
        // the app is suspended; only the confirmed exit action should end
        // and save a flight. Position callbacks are managed by the system across the
        // inactive/active transition.
    }

    function pollPosition() as Void {
        updateHealthMetrics();
        var info = Position.getInfo();
        if (info != null) {
            onPosition(info);
        }
    }

    function enableHealthSensors() as Void {
        try {
            Sensor.setEnabledSensors([
                Sensor.SENSOR_HEARTRATE,
                Sensor.SENSOR_TEMPERATURE
            ]);
        } catch (exception) {
            // Health values remain unavailable when a device does not expose
            // one of the requested sensors.
        }
    }

    function updateHealthMetrics() as Void {
        try {
            mSensorInfo = Sensor.getInfo();
        } catch (exception) {
            mSensorInfo = null;
        }

        try {
            mActivityMonitorInfo = ActivityMonitor.getInfo();
        } catch (exception) {
            mActivityMonitorInfo = null;
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

    function startPositionTracking() as Void {
        enablePositioning();
        mPositionTimer.start(method(:pollPosition), 1000, true);
        pollPosition();
    }

    function stopPositionTracking() as Void {
        mPositionTimer.stop();
        try {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        } catch (exception) {
            // The FIT session is still stopped even if a device rejects the
            // location disable request during a lifecycle transition.
        }
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
            applyPendingManualAltitude();
            if (mPendingNearestCalibration && canCalibrateNearestAirport()) {
                mPendingNearestCalibration = false;
                requestAltitudeCalibration();
            }
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
                :category => closest[6],
                :elevationFeet => closest[7]
            };
        }
    }

    function toggleRecording() {
        if (mSession == null) {
            startRecording();
        } else if (isRecording()) {
            pauseRecording();
        } else {
            resumeRecording();
        }
        WatchUi.requestUpdate();
    }

    function startRecording() {
        if (mSession != null) {
            return resumeRecording();
        }

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
            mPausedMoment = null;
            mPausedSeconds = 0;
            mVerticalSpeedMps = null;
            mStatus = "RECORDING";
            showRecordingFeedback();
            playRecordingFeedback(true);
            return true;
        } catch (exception) {
            mSession = null;
            mStartMoment = null;
            mStatus = "START FAILED";
            return false;
        }
    }

    function pauseRecording() {
        if (!isRecording()) {
            mStatus = "PAUSED";
            return false;
        }

        try {
            if (!mSession.stop()) {
                mStatus = "PAUSE FAILED";
                return false;
            }
            stopPositionTracking();
            mPausedMoment = Time.now();
            mStatus = "PAUSED";
            playRecordingFeedback(false);
            return true;
        } catch (exception) {
            mStatus = "PAUSE FAILED";
            return false;
        }
    }

    function resumeRecording() {
        if (mSession == null) {
            return startRecording();
        }
        if (isRecording()) {
            mStatus = "ALREADY RECORDING";
            return false;
        }

        try {
            if (!mSession.start()) {
                mStatus = "RESUME FAILED";
                return false;
            }
            startPositionTracking();
            if (mPausedMoment != null) {
                mPausedSeconds += Time.now().subtract(mPausedMoment).value();
                mPausedMoment = null;
            }
            mStatus = "RECORDING";
            showRecordingFeedback();
            playRecordingFeedback(true);
            return true;
        } catch (exception) {
            mStatus = "RESUME FAILED";
            return false;
        }
    }

    function saveRecordingAndExit() {
        if (mSession == null) {
            System.exit();
            return;
        }

        try {
            stopPositionTracking();
            if (isRecording() && !mSession.stop()) {
                mStatus = "STOP FAILED";
                WatchUi.requestUpdate();
                return;
            }
            if (!mSession.save()) {
                mStatus = "SAVE FAILED";
                WatchUi.requestUpdate();
                return;
            }
            mSession = null;
            mStartMoment = null;
            mPausedMoment = null;
            mPausedSeconds = 0;
            mStatus = "SAVED - SYNC";
            System.exit();
        } catch (exception) {
            mStatus = "SAVE FAILED";
            WatchUi.requestUpdate();
        }
    }

    function resumeLaterAndExit() {
        if (mSession == null) {
            System.exit();
            return;
        }

        try {
            if (isRecording() && !pauseRecording()) {
                mStatus = "PAUSE FAILED";
                WatchUi.requestUpdate();
                return;
            }
            // Leave the unfinished Session open. ActivityRecording keeps the
            // single unfinished session available to createSession() when the
            // app is opened again, where Select can resume it.
            System.exit();
        } catch (exception) {
            mStatus = "RESUME LATER FAILED";
            WatchUi.requestUpdate();
        }
    }

    function discardRecordingAndExit() {
        if (mSession == null) {
            System.exit();
            return;
        }

        try {
            stopPositionTracking();
            if (isRecording() && !mSession.stop()) {
                mStatus = "STOP FAILED";
                WatchUi.requestUpdate();
                return;
            }
            if (!mSession.discard()) {
                mStatus = "DISCARD FAILED";
                WatchUi.requestUpdate();
                return;
            }
            mSession = null;
            mStartMoment = null;
            mPausedMoment = null;
            mPausedSeconds = 0;
            mStatus = "DISCARDED";
            System.exit();
        } catch (exception) {
            mStatus = "DISCARD FAILED";
            WatchUi.requestUpdate();
        }
    }

    function isRecording() {
        return mSession != null && mSession.isRecording();
    }

    function hasRecordingSession() {
        return mSession != null;
    }

    // 0 = hidden, 1 = paused (permanent red), 2 = just started/resumed (green).
    function recordingIndicatorState() {
        if (mSession != null && !isRecording()) {
            return 1;
        }
        if (mRecordingFeedbackUntil != null &&
            Time.now().value() < mRecordingFeedbackUntil) {
            return 2;
        }
        return 0;
    }

    function showRecordingFeedback() {
        mRecordingFeedbackUntil = Time.now().value() + 3;
    }

    function getPositionInfo() {
        return mPositionInfo;
    }

    function requestAltitudeSourceSelection() {
        if (mAltitudeSourcePromptShown || mSession != null) {
            return;
        }
        mAltitudeSourcePromptShown = true;

        showAltitudeSourceMenu();
    }

    function showAltitudeSourceMenu() {

        var menu = new WatchUi.Menu();
        menu.setTitle("ALTITUDE SOURCE");
        menu.addItem("GARMIN ALTITUDE", :garmin);
        menu.addItem("NEAREST AIRPORT", :airport);
        menu.addItem("MANUAL HEIGHT", :manual);
        WatchUi.pushView(
            menu,
            new FlightTraceAltitudeSourceMenuDelegate(self),
            WatchUi.SLIDE_IMMEDIATE
        );
    }

    function isWaitingForNearestCalibration() {
        return mPendingNearestCalibration;
    }

    function reopenAltitudeSourceSelection() {
        mPendingNearestCalibration = false;
        mStatus = "READY";
        showAltitudeSourceMenu();
    }

    function selectAltitudeSource(item) {
        if (item == :garmin) {
            mAltitudeCalibrationFeet = null;
            mAltitudeCalibrationAirport = null;
            mPendingManualAltitudeFeet = null;
            mPendingNearestCalibration = false;
            mStatus = "GARMIN ALTITUDE";
            WatchUi.requestUpdate();
        } else if (item == :airport) {
            if (canCalibrateNearestAirport()) {
                requestAltitudeCalibration();
            } else {
                mPendingNearestCalibration = true;
                if (mNearestAirport == null) {
                    mStatus = "WAITING FOR GPS";
                } else if (mNearestAirport[:elevationFeet] == null) {
                    mStatus = "NO AIRPORT ELEVATION";
                } else {
                    mStatus = "STOP TO CALIBRATE";
                }
                WatchUi.requestUpdate();
            }
        } else if (item == :manual) {
            mPendingNearestCalibration = false;
            var initialText = "0";
            if (getDisplayedAltitudeFeet(mPositionInfo) != null) {
                initialText = getDisplayedAltitudeFeet(mPositionInfo).format("%0.0f");
            }
            WatchUi.pushView(
                new WatchUi.TextPicker(initialText),
                new FlightTraceManualAltitudeDelegate(self),
                WatchUi.SLIDE_IMMEDIATE
            );
        }
    }

    function getDisplayedAltitudeFeet(info) {
        if (info == null || info.altitude == null) {
            return null;
        }
        var altitudeFeet = info.altitude * 3.28084;
        if (mAltitudeCalibrationFeet != null) {
            altitudeFeet += mAltitudeCalibrationFeet;
        }
        return altitudeFeet;
    }

    function canCalibrateNearestAirport() {
        if (mNearestAirport == null ||
            mNearestAirport[:elevationFeet] == null ||
            mNearestAirport[:distanceMeters] > 1852.0) {
            return false;
        }
        if (mPositionInfo == null || mPositionInfo.position == null) {
            return false;
        }
        // A stationary watch can legitimately report no speed value.  A
        // non-null speed above 5 kt is still rejected as unsafe for a ground
        // elevation calibration.
        if (mPositionInfo.speed != null && mPositionInfo.speed > 2.57222) {
            return false;
        }
        return getDisplayedAltitudeFeet(mPositionInfo) != null;
    }

    function requestAltitudeCalibration() {
        if (!canCalibrateNearestAirport()) {
            return;
        }
        var airport = mNearestAirport;
        WatchUi.pushView(
            new WatchUi.Confirmation("CALIBRATE " + airport[:ident] + " " +
                airport[:elevationFeet].format("%d") + " FT?"),
            new FlightTraceCalibrationConfirmationDelegate(self),
            WatchUi.SLIDE_IMMEDIATE
        );
    }

    function applyAltitudeCalibration() {
        if (!canCalibrateNearestAirport()) {
            return;
        }
        var rawAltitudeFeet = getDisplayedAltitudeFeet(mPositionInfo);
        mAltitudeCalibrationFeet = mNearestAirport[:elevationFeet] - rawAltitudeFeet;
        mAltitudeCalibrationAirport = mNearestAirport[:ident];
        mPendingNearestCalibration = false;
        WatchUi.requestUpdate();
    }

    function applyManualAltitudeText(text) {
        var targetFeet = null;
        try {
            targetFeet = text.toNumber();
        } catch (exception) {
            targetFeet = null;
        }

        if (targetFeet == null || targetFeet < -2000 || targetFeet > 60000) {
            mStatus = "INVALID ALTITUDE";
            WatchUi.requestUpdate();
            return;
        }

        mPendingManualAltitudeFeet = targetFeet;
        applyPendingManualAltitude();
        WatchUi.requestUpdate();
    }

    function applyPendingManualAltitude() {
        if (mPendingManualAltitudeFeet == null ||
            getDisplayedAltitudeFeet(mPositionInfo) == null) {
            return;
        }
        mAltitudeCalibrationFeet = mPendingManualAltitudeFeet -
            getDisplayedAltitudeFeet(mPositionInfo);
        mAltitudeCalibrationAirport = null;
        mPendingManualAltitudeFeet = null;
        mStatus = "MANUAL ALTITUDE";
    }

    function getAltitudeCalibrationFeet() {
        return mAltitudeCalibrationFeet;
    }

    function getSensorInfo() {
        return mSensorInfo;
    }

    function getActivityMonitorInfo() {
        return mActivityMonitorInfo;
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
        var altitudeFeet = getDisplayedAltitudeFeet(mPositionInfo);
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

    function showHealthPage() {
        mPage = 3;
        WatchUi.requestUpdate();
    }

    function showNextPage() {
        mPage = (mPage + 1) % 4;
        WatchUi.requestUpdate();
    }

    function showPreviousPage() {
        mPage = (mPage + 3) % 4;
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

        var endMoment = mPausedMoment == null ? Time.now() : mPausedMoment;
        var elapsed = endMoment.subtract(mStartMoment).value() - mPausedSeconds;
        return elapsed < 0 ? 0 : elapsed;
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
