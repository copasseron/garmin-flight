# Data sources and notices

The MIT license in `LICENSE` applies only to the original source code and
documentation of this repository. It does not replace the terms of the
external data sources, SDKs, or third-party assets listed below.

## Flight-assistant safety notice

This project is a non-certified informational flight assistant. It is not a
primary navigation source, an airspace-authority service, or certified
avionics. Do not rely on it as the sole source for position, airspace status,
frequencies, runway information, terrain clearance, or flight decisions.
Always cross-check current official AIP/VAC information, NOTAMs, charts, ATC
instructions, and approved aircraft equipment. The pilot remains responsible
for verifying the information and operating safely.

## SIA airspace data

`source/FranceAirspaces.mc` is a generated, transformed and filtered dataset
derived from the Service de l'Information Aéronautique (SIA) AIXM 4.5 XML
export:

- source: [SIA XML AIRAC products](https://www.sia.aviation-civile.gouv.fr/produits-numeriques-en-libre-disposition.html)
- source cycle embedded in this repository: AIRAC 09/26
- source export date: 2026-09-03
- licence: [SIA open-data licence](https://www.sia.aviation-civile.gouv.fr/pub/media/news/file/l/i/licenceopendata-vf_2.pdf)

The watch dataset keeps the P, TMA and CTR zones needed by the application and
omits R and D zones to fit the epix2 memory budget. It is not the complete SIA
export. The generator keeps the source AIRAC label and can be rerun from a
newer export; the raw ZIP is intentionally ignored by Git.

When redistributing or regenerating this data, keep the SIA attribution, the
date of the last update, and the source link required by the SIA licence. This
derived dataset is not presented as an official SIA product or as an
endorsement by the SIA. It is supplied for software and simulator use, without
operational guarantee, and must never be treated as a primary aeronautical
source. Always verify current official aeronautical information, including AIP,
VAC and NOTAM information, before flight.

## Airport reference data

`source/FranceAirports.mc` is a mixed-provenance informational reference. Its
records combine SIA AIRAC material with OurAirports data and local references
for some ULM, private and military aerodromes. The provenance comments in the
source file should be kept with the dataset.

- OurAirports data: [download and data information](https://ourairports.com/data/)
- OurAirports terms: the published airport data is released into the public
  domain, without a guarantee of accuracy or completeness.
- SIA-derived airport information remains subject to the SIA licence and
  attribution requirements above.

Airport frequencies, runway designations and category labels are convenience
data for the application and simulator. They are not a substitute for current
official aeronautical publications.

## Garmin Connect IQ

The Garmin Connect IQ SDK is not bundled in this repository. It must be
installed separately under Garmin's SDK terms. Garmin, Connect IQ, epix and
related marks belong to Garmin Ltd. or its affiliates.

Do not commit a developer key, SDK installation, generated PRG/IQ build
artifacts, or local simulator captures. The repository `.gitignore` excludes
the signing key, SDK helper directory, build outputs, source ZIP exports and
the local capture filename used during development.

## Third-party visual assets

Before publishing files under `assets/` or modified drawable images, confirm
that their source and licence permit redistribution. The MIT licence does not
automatically cover images or other assets that were obtained elsewhere.
