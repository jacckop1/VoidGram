"""Source-level regression checks for native video conversion integration.

These do not substitute for an Xcode compile or a real iPhone media-send test.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class VideoConversionPortTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text(encoding="utf-8")

    def test_preview_controls_and_crop(self):
        code = self.read("native/VGMediaConversion.inc")
        for token in (
            "vgNoteTapped", "vgVoiceTapped", "VGVideoCropScreen",
            "UIPanGestureRecognizer", "UIPinchGestureRecognizer",
            "AVAssetExportPresetAppleM4A", "AVAssetExportPresetHighestQuality",
            "CGSizeMake(640, 640)", "AVFileTypeMPEG4", "AVFileTypeAppleM4A",
        ):
            self.assertIn(token, code)

    def test_real_media_attributes(self):
        patch = self.read("patches/voidgram-video-attributes.patch")
        self.assertIn("isVoice: true", patch)
        self.assertIn(".instantRoundVideo", patch)
        self.assertIn("isFile: !(isVGVoice || isVGNote)", patch)
        self.assertIn("vgvoice_", patch)
        self.assertIn("vgnote_", patch)

    def test_native_patch_pipeline(self):
        prepare = self.read("ci/prepare.py")
        for file in (
            "voidgram-video-preview-ui.patch",
            "voidgram-video-description.patch",
            "voidgram-video-attributes.patch",
            "voidgram-video-build.patch",
        ):
            self.assertIn(file, prepare)
        self.assertIn('VGMediaConversion.h', prepare)
        self.assertIn('shutil.copy2(conversion_source, conversion_target)', prepare)
        view = self.read("patches/voidgram-video-preview-ui.patch")
        self.assertIn('#import "VGMediaConversion.h"', view)
        self.assertIn("vgIsConversionButton:view", view)
        self.assertIn("vgExportInProgress", view)

if __name__ == "__main__":
    unittest.main()
