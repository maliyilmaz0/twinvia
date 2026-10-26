import json
from pathlib import Path
import plistlib
import struct
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"


class BrandAssetsTests(unittest.TestCase):
    def test_rebrand_preserves_platform_identities_and_legacy_scheme(self):
        info = plistlib.loads((ROOT / "apps/macos/Configuration/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDisplayName"], "Twinvia")
        self.assertEqual(info["CFBundleIdentifier"], "dev.androfest.macos")
        schemes = {s for record in info["CFBundleURLTypes"] for s in record["CFBundleURLSchemes"]}
        self.assertTrue({"twinvia", "androfest"}.issubset(schemes))
        gradle = (ROOT / "apps/android/app/build.gradle.kts").read_text()
        self.assertIn('applicationId = "dev.androfest.android"', gradle)

    def test_mac_icon_catalog_contains_correct_native_pixel_sizes(self):
        root = ROOT / "apps/macos/Sources/Twinvia/Assets.xcassets"
        for name, count in [("AppIcon.appiconset", 10), ("TrayMark.imageset", 3)]:
            catalog = root / name
            data = json.loads((catalog / "Contents.json").read_text())
            self.assertEqual(len(data["images"]), count)
            for image in data["images"]:
                png = (catalog / image["filename"]).read_bytes()
                self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
                pixels = int(image.get("size", "18x18").split("x")[0]) * int(image["scale"][0])
                self.assertEqual(struct.unpack(">II", png[16:24]), (pixels, pixels))
            if name == "TrayMark.imageset":
                self.assertEqual(data["properties"]["template-rendering-intent"], "template")

    def test_android_adaptive_and_monochrome_icons_are_bound(self):
        res = ROOT / "apps/android/app/src/main/res"
        icon = ET.parse(res / "mipmap-anydpi-v26/ic_launcher.xml").getroot()
        self.assertEqual(icon.tag, "adaptive-icon")
        self.assertEqual({node.tag for node in icon}, {"background", "foreground", "monochrome"})
        for node in icon:
            reference = node.get(ANDROID + "drawable")
            if reference.startswith("@drawable/"):
                self.assertTrue((res / "drawable" / (reference.split("/")[1] + ".xml")).is_file())
        for filename in ("mark.svg", "app-icon.svg", "banner.svg"):
            self.assertEqual(ET.parse(ROOT / "assets/brand" / filename).getroot().tag,
                             "{http://www.w3.org/2000/svg}svg")


if __name__ == "__main__":
    unittest.main()
