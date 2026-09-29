# Flight Trace

A Garmin Connect IQ flight assistant for the Garmin epix Gen 2. It records a manually started flight as a normal Garmin activity so the GPS trace can be reviewed in Garmin Connect.

> **Safety notice:** Flight Trace is an informational flight assistant only. It
> must not be used as the primary source for navigation, airspace status,
> frequencies, runway information, or flight decisions. Always use current
> official aeronautical publications, charts, NOTAMs, ATC instructions, and
> approved aircraft equipment as the primary sources. The pilot remains
> responsible for verifying all information before and during flight.

## MVP behavior

- Press the physical Select button to start a flight.
- Press the physical Select button again to stop and save it.
- Touch and swipe input are disabled intentionally; use the physical Select,
  Up, and Down buttons only.
- The main round-screen page shows magnetic track, vertical speed in feet per minute, groundspeed in knots, elapsed activity time, UTC time, altitude, and GPS/recording status.
- Press the Down button to open a second page showing the nearest French airport, distance in nautical miles, and magnetic bearing. Press Up to return to the flight page.
- Press Down again to open the current-airspace page. It shows the most restrictive active zone at the GPS position, its class, published frequencies, vertical limits, activation state, and AIRAC label. Up and Down cycle through the three pages.
- The magnetic declination is configurable in the app settings and defaults to `0°`. Enter east declination as positive and west declination as negative.
- Units are aviation-friendly: feet, knots, degrees, and feet per minute.
- The saved FIT activity uses Garmin's `Flying` sport classification and is intended to sync through Garmin Connect.

The nearest-airport reference list covers France and includes 435 airports and aerodromes with ICAO or GPS identifiers. Each bundled record contains the identifier, name, coordinates, the primary published TWR, AFIS, or A/A frequency, the two longest runway pairs (or `WATER` for a seaplane base), and a metadata-based MILITARY, PRIVATE, or CIVILIAN category. Frequency and runway values were checked against the SIA AIRAC 09/26 VAC/AIP material where available, with documented ULM/private/military references used for entries outside the current SIA VAC set. It is an informational convenience feature, not an operational AIP database: ownership/category metadata may be incomplete, and it does not assess runway suitability, access restrictions, weather, or NOTAMs. Verify current aeronautical information before flight.

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
5. Select the `epix2` round device profile. Use the simulator's activity data controls to provide GPS data, then press Select to start and stop the recording. Use the Down and Up buttons to preview the airport and flight pages.
6. To test the magnetic correction, open `File > Edit Persistent Storage > Edit Application.Properties data` in the simulator and set the declination value.

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
                    Unified bundled France airport records
source/FranceAirspaces.mc
                    Generated compact SIA airspace records and frequencies for
                    metropolitan France. The current AIRAC export is filtered
                    to P, TMA, and CTR zones and keeps the short zone
                    name, polygon vertices, vertical limits, and two primary
                    frequencies.
tools/airspace/
                    SIA AIXM 4.5 ZIP to Monkey C dataset converter and tests
```

## Refresh the airspace dataset

Download the current free `export_xml_bd_SIAAAAA-MM-JJ.zip` from the [SIA XML AIRAC product](https://www.sia.aviation-civile.gouv.fr/produits-numeriques-en-libre-disposition/les-bases-de-donnees-sia/donnees-aeronautiques-xml-airac-09-26.html), then run from the project root:

```text
python3 tools/airspace/build_airspace_dataset.py \
  ~/Downloads/export_xml_bd_SIA2026-09-03.zip \
  --airac 09/26 \
  --omit-types R,D \
  --output source/FranceAirspaces.mc \
  --report /private/tmp/airspace-quality.json
```

The watch build omits R and D zones because the epix2 memory budget cannot hold every polygon in the full AIXM export. The complete SIA XML remains the authoritative source; the embedded subset keeps P, TMA, and CTR zones, including zones without a published frequency. The report still counts every selected zone, missing geometry or frequencies, and broken service/channel links. A zone can have several radio services; the generator keeps the two highest-ranked primary frequencies in the embedded watch data, and the SIA source date and AIRAC label remain in the generated file and on the watch page.

## Licensing and data sources

The original application code and repository documentation are released under
the [MIT License](LICENSE). External data has separate terms: the embedded
airspace dataset is derived from the [SIA AIXM AIRAC export](https://www.sia.aviation-civile.gouv.fr/produits-numeriques-en-libre-disposition.html)
under the [SIA open-data licence](https://www.sia.aviation-civile.gouv.fr/pub/media/news/file/l/i/licenceopendata-vf_2.pdf),
and the airport reference data also includes [OurAirports public-domain data](https://ourairports.com/data/)
and documented local references. See [DATA-LICENSE.md](DATA-LICENSE.md) for
the attribution, source dates, filtering, redistribution notes, and Garmin
SDK/asset notices.

This is an informational flight-assistant, simulator, and watch application,
not an operational navigation database or certified avionics system. It is
never a primary source for navigation or aeronautical decision-making. Check
current official aeronautical information before flight.

## Garmin references

- [ActivityRecording API](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html)
- [Position API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Position.html)
- [epix Gen 2 compatibility](https://developer.garmin.com/connect-iq/compatible-devices/)
- [Connect IQ project and build commands](https://developer.garmin.com/connect-iq/reference-guides/visual-studio-code-extension/)
