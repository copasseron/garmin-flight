# Flight Trace

Flight Trace is a Garmin Connect IQ flight assistant for compatible Garmin
watches. It records a manually started flight as a Garmin activity and provides
compact offline airport and airspace information.

> **Safety notice:** This is an informational, non-certified flight assistant.
> It must never be the primary source for navigation, airspace status,
> frequencies, runways, or flight decisions. Always cross-check current AIP,
> VAC, NOTAMs, charts, ATC instructions, and approved aircraft equipment.

## Features

- Flight recording with GPS track, altitude, speed, magnetic track and vertical speed.
- Nearest-airport page with ICAO identifier, distance, magnetic bearing, radio frequency and runways.
- Ground altimeter calibration against the nearest airport elevation, with confirmation and a 1 NM / near-zero-speed guard.
- Current-airspace page for P, TMA and CTR zones, with class, limits and published frequencies.
- Health page with heart rate, respiration, oxygen saturation and temperature when available.
- Three pages navigated with the physical `Up` and `Down` buttons.
- Physical `Select` button to start and stop recording. Touch and swipe input are disabled.
- French airport and airspace data bundled offline; no network connection is required on the watch.
- Airport callouts use the compact SIA AIXM/VAC name where it is published (for example `LFPZ` displays `SAINT CYR`).

## Build

Requirements:

- Garmin Connect IQ SDK 9.2.0 or newer
- Java 11 or newer
- One of the validated Garmin device profiles below
- Monkey C extension for Visual Studio Code

Open the project in Visual Studio Code, choose a device profile, then run
**Monkey C: Build Current Project** and **Run Without Debugging**. Use the
simulator's GPS controls to set a position. The app uses physical simulator
buttons only.

For a physical watch, use **Monkey C: Build for Device**. Never commit the
developer key or generated build files.

To install a generated package manually, connect the watch by USB, open its
`GARMIN/APPS` folder, and copy the `.prg` built for that exact device profile
into it. Eject the watch before disconnecting it. The app then appears in the
watch's Apps list. For example, use `flight-trace-epix2.prg` for an epix Gen 2;
use the matching profile for another watch.

### GitHub Actions packages

The repository workflow builds one signed `.prg` per supported device. Add a
repository secret named `GARMIN_DEVELOPER_KEY_B64` containing the base64 form of
your local `developer_key`:

```bash
base64 -i developer_key | tr -d '\n' | pbcopy
```

Paste the clipboard value into GitHub repository **Settings → Secrets and
variables → Actions**. Pushes and pull requests produce downloadable workflow
artifacts. To publish packages in a GitHub Release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release contains the `.prg` matching each watch profile.

## Compatibility

Validated with Connect IQ SDK 9.2.0 on the simulator. Every listed profile was
checked on the three pages with a GPS fix, airport data and active airspace data:

- `epix2`: epix Gen 2 and quatix 7 Sapphire, 416×416
- `fenix7`: fēnix 7 and quatix 7, 260×260
- `fenix7x`: fēnix 7X and Enduro 2 family, 280×280
- `enduro3`: Enduro 3, 280×280
- `fr165`: Forerunner 165, 390×390
- `fr265`: Forerunner 265, 416×416
- `fr955`: Forerunner 955 / Solar, 260×260
- `fr965`: Forerunner 965, 454×454
- `fr970`: Forerunner 970, 454×454

The checks covered the flight, nearest-airport and current-airspace screens:
all displayed fields remained inside the watch face with no text overlap or
clipping. Simulator validation is not a substitute for an on-watch test.

The epix2 is the only profile validated on real hardware. All other profiles
are best-effort simulator validations and should be tested on the target watch
before use.

## Screenshots

<p align="center">
  <img src="docs/screenshots/flight-page.png" alt="Flight page" width="280">
  <img src="docs/screenshots/nearest-airport-page.png" alt="Nearest airport page" width="280">
  <img src="docs/screenshots/airspace-page.png" alt="Current airspace page" width="280">
</p>

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

To refresh the compact airport callouts from the same SIA ZIP:

```text
python3 tools/airports/build_airport_names.py \
  ~/Downloads/export_xml_bd_SIA2026-09-03.zip \
  --output source/FranceAirports.mc \
  --report /private/tmp/airport-names-report.json
```

The generator reads the official AIXM `Uni/txtName` values, removes the ICAO
prefix and replaces the airport name field with that compact callout. It also
reports airport records not represented in that AIXM export; those local-only
records receive a compact fallback from the existing reference name.

The same export supplies `Ahp/valElev` in feet for airport elevation. If an
airport has no published elevation, the calibration action is not offered.

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
