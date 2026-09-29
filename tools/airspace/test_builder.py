import json
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from build_airspace_dataset import emit_module, parse_airspaces


class AirspaceBuilderTests(unittest.TestCase):
    def test_resolves_geometry_altitude_and_frequency(self):
        fixture = Path(__file__).parent / "fixtures" / "sample_aixm.xml"
        zones, report = parse_airspaces(ET.parse(fixture).getroot())
        self.assertEqual(report["zones"], 1)
        self.assertEqual(zones[0]["id"], "DEMO_CTR")
        self.assertEqual(zones[0]["floor"], 0.0)
        self.assertEqual(zones[0]["ceiling"], 2500.0)
        self.assertEqual(zones[0]["frequencies"][0]["serviceType"], "TWR")
        self.assertEqual(zones[0]["frequencies"][0]["frequencyTx"], "118.700")

    def test_emits_monkey_module(self):
        fixture = Path(__file__).parent / "fixtures" / "sample_aixm.xml"
        zones, _ = parse_airspaces(ET.parse(fixture).getroot())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "FranceAirspaces.mc"
            emit_module(zones, "TEST", output)
            contents = output.read_text(encoding="utf-8")
            self.assertIn('"DEMO CTR"', contents)
            self.assertIn('"118.700"', contents)


if __name__ == "__main__":
    unittest.main()
