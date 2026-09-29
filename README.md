# Flight Trace

Flight Trace is a Garmin Connect IQ flight assistant for the Garmin epix Gen 2.
It records a manually started flight as a Garmin activity and provides compact
offline airport and airspace information.

> **Safety notice:** This is an informational, non-certified flight assistant.
> It must never be the primary source for navigation, airspace status,
> frequencies, runways, or flight decisions. Always cross-check current AIP,
> VAC, NOTAMs, charts, ATC instructions, and approved aircraft equipment.

## Features

- Flight recording with GPS track, altitude, speed, magnetic track and vertical speed.
- Nearest-airport page with ICAO identifier, distance, magnetic bearing, radio frequency and runways.
- Current-airspace page for P, TMA and CTR zones, with class, limits and published frequencies.
- Three pages navigated with the physical `Up` and `Down` buttons.
- Physical `Select` button to start and stop recording. Touch and swipe input are disabled.
- French airport and airspace data bundled offline; no network connection is required on the watch.

## Build

Requirements:

- Garmin Connect IQ SDK 9.2.0 or newer
- Java 11 or newer
- Garmin epix Gen 2 simulator or watch
- Monkey C extension for Visual Studio Code

Open the project in Visual Studio Code, choose `epix2`, then run **Monkey C:
Build Current Project** and **Run Without Debugging**. Use the simulator's GPS
controls to set a position. The app uses physical simulator buttons only.

For a physical watch, use **Monkey C: Build for Device**. Never commit the
developer key or generated build files.

## Screenshots

![Flight page](docs/screenshots/flight-page.png)

![Nearest airport page](docs/screenshots/nearest-airport-page.png)

![Current airspace page](docs/screenshots/airspace-page.png)

The airspace page opens with `Down` from the airport page. These are complete
watch-screen simulator captures; always verify the current build and current
aeronautical data before flight.

## Refresh the airspace data

The converter reads an official SIA AIXM 4.5 AIRAC ZIP and generates the compact
Monkey C dataset:

```text
python3 tools/airspace/build_airspace_dataset.py \
  ~/Downloads/export_xml_bd_SIA2026-09-03.zip \
  --airac 09/26 \
  --omit-types R,D \
  --output source/FranceAirspaces.mc \
  --report /private/tmp/airspace-quality.json
```

The epix2 build keeps P, TMA and CTR zones to stay within the watch memory
budget. The full source export is not embedded.

## Data and licence

Original code and documentation: [MIT License](LICENSE).

Airspace data: SIA AIXM AIRAC export under the [SIA open-data licence](https://www.sia.aviation-civile.gouv.fr/pub/media/news/file/l/i/licenceopendata-vf_2.pdf).
Airport data also uses [OurAirports public-domain data](https://ourairports.com/data/)
and documented local references. Details, attribution and redistribution notes
are in [DATA-LICENSE.md](DATA-LICENSE.md).

## Repository layout

```text
source/       Monkey C application and bundled datasets
resources/    App resources and settings
tools/        AIXM converter and tests
assets/       App artwork
```

Run the converter tests with:

```text
python3 -m unittest discover -s tools/airspace -p 'test_*.py'
```
