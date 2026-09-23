# Flight Trace

A Garmin Connect IQ device app for the Garmin epix Gen 2. It records a manually started flight as a normal Garmin activity so the GPS trace can be reviewed in Garmin Connect.

## MVP behavior

- Press Select or tap the screen to start a flight.
- Press Select or tap again to stop and save it.
- The live screen shows the nearest French airport, distance in nautical miles, true bearing, altitude, groundspeed, and GPS status.
- Units are aviation-friendly: feet, knots, degrees, and feet per minute.
- The saved FIT activity is intended to sync through Garmin Connect.

The nearest-airport reference list covers France and includes 196 airports and aerodromes with ICAO identifiers. It is bundled offline and currently comes from the [public-domain OurAirports dataset](https://ourairports.com/data/) downloaded on 2026-09-23. It is an informational convenience feature, not an operational AIP database: it does not assess runway suitability, access restrictions, military status, weather, or NOTAMs. Verify current aeronautical information before flight.

There is no companion phone app, web service, custom map, GPX exporter, flight-plan support, or multi-device support in this MVP.

## Requirements

- Garmin Connect IQ SDK 9.2.0 or newer.
- Java 11 or newer for the Garmin compiler and simulator tools.
- Garmin epix Gen 2 simulator and/or physical watch.
- Visual Studio Code with Garmin's Monkey C extension.
- A Garmin developer account and developer key for installing builds on a physical device.

Install the SDK through Garmin's [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/), then install the Monkey C extension from the Visual Studio Code extension marketplace. Open this folder in Visual Studio Code and run `Monkey C: Verify Installation`.

## Build and run

1. Open the project in Visual Studio Code.
2. Select `Monkey C: Build Current Project`.
3. Choose `epix2` as the target device.
4. Run without debugging to open the simulator.
5. Use the simulator's activity data controls to provide GPS data, then press Select to start and stop the recording.

For a physical-watch build, use `Monkey C: Build for Device`, choose `epix2`, and install the generated PRG using Garmin's normal developer workflow. Do not commit the generated developer key or build artifacts.

## Physical-watch acceptance test

1. Install the app on the epix Gen 2.
2. Go outside and wait for a usable GPS fix.
3. Start the flight from the app's main screen.
4. Record at least 30 minutes.
5. Stop the recording and allow the watch to save it.
6. Sync the watch with Garmin Connect.
7. Confirm that the activity has a visible route, timestamps, and the expected flight duration.

Also test starting twice, stopping when no flight is active, losing GPS temporarily, and leaving/reopening the app while recording. The FIT activity recording is the authoritative route; live position callbacks are only used to update the screen.

## Project layout

```text
manifest.xml       Connect IQ app metadata and epix2 target
monkey.jungle      Connect IQ build configuration
source/             Monkey C application, view, and input delegate
resources/          Localized app strings
source/FranceAirports.mc
                    Bundled France airport reference points
```

## Garmin references

- [ActivityRecording API](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html)
- [Position API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Position.html)
- [epix Gen 2 compatibility](https://developer.garmin.com/connect-iq/compatible-devices/)
- [Connect IQ project and build commands](https://developer.garmin.com/connect-iq/reference-guides/visual-studio-code-extension/)
