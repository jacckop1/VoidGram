"""Source-assembly regressions for native Video -> Voice / Video Note.

Run locally with: python3 -m unittest ci.tests.test_video_conversion
No macOS/Xcode runner or IPA build is required for these checks.
"""
import tempfile
import unittest
from pathlib import Path

from ci.video_conversion import apply, replace_once


ROOT = Path(__file__).resolve().parents[2]


class VideoConversionPortTests(unittest.TestCase):
    def write(self, root, path, content):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        return target

    def test_rejects_unknown_upstream_anchor(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.swift"
            path.write_text("upstream changed", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "occurs 0 times"):
                replace_once(path, "old expected anchor", "replacement")

    def test_rejects_ambiguous_upstream_anchor(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.swift"
            path.write_text("anchor\nanchor\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "occurs 2 times"):
                replace_once(path, "anchor", "replacement")

    def test_installs_both_controls_and_real_media_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            upstream = Path(directory)
            self.write(upstream, "submodules/TelegramUI/Sources/ChatController.swift",
                       "            AyuPluginChatTracker.current = self\n")
            self.write(upstream, "submodules/MediaPickerUI/Sources/LegacyMediaPickerGallery.swift",
                       "    var transitionedIn = false\n    controller.itemFocused = { item in\n"
                       "        if let item = item as? TGMediaPickerGalleryItem { }\n    }\n")
            self.write(upstream, "submodules/TelegramUI/Sources/AyuVideoCircle.swift",
                       "import Foundation\n"
                       "    static func convert(path: String, completion: @escaping (URL?, Double) -> Void) {\n"
                       "        let output: CGFloat = 384.0\n"
                       "    }\n"
                       "    static func send(path: String, to chat: ChatControllerImpl) {\n"
                       "        convert(path: path, completion: { [weak chat] url, duration in\n"
                       "            let size = PixelDimensions(width: 384, height: 384)\n"
                       "        })\n    }\n")
            apply(upstream, ROOT)
            gallery = (upstream / "submodules/MediaPickerUI/Sources/LegacyMediaPickerGallery.swift").read_text()
            circle = (upstream / "submodules/TelegramUI/Sources/AyuVideoCircle.swift").read_text()
            chat = (upstream / "submodules/TelegramUI/Sources/ChatController.swift").read_text()
            self.assertIn("ayuVideoActions.update(item: item)", gallery)
            self.assertIn("AyuVideoPickerExporter.prepare", gallery)
            self.assertIn("AyuVideoRoundCropController", gallery)
            self.assertIn("AyuAudioToVoice.send", chat)
            self.assertIn("AyuVideoCircle.send", chat)
            self.assertIn("PixelDimensions(width: 640, height: 640)", circle)
            self.assertIn("crop: AyuMediaVideoCrop? = nil", circle)
            self.assertTrue((upstream / "submodules/TelegramCore/Sources/AyuGram/AyuMediaConversionBridge.swift").exists())
            self.assertTrue((upstream / "submodules/MediaPickerUI/Sources/AyuVideoPreviewActions.swift").exists())


if __name__ == "__main__":
    unittest.main()
