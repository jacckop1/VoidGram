# Native Video → Voice / Video Note (development branch)

This feature is implemented in the original Telegram-iOS photo/video gallery and media enqueue pipeline. It is **not** an injected dylib.

## User flow

Open a video in Telegram's attachment preview. Two buttons appear:
- **◉ Video Note** opens a circular cropping screen. Pan to reposition the picture, pinch to zoom (1–4×), and tap **اعتماد الفيديو نوت**. The video is exported to a real square 640×640 MP4 (H.264-compatible export preset) with audio, capped at 60 seconds. The blue Note button indicates the output is ready.
- **♫ Voice** exports the video audio to a temporary M4A and marks it as a Telegram voice message. The blue Voice button indicates the output is ready.

The selected mode is per asset, not a global switch. Press the active button again to revert to sending the original video. Normal video selection remains unchanged.

Sending is blocked while conversion is in progress, so it cannot accidentally transmit the original video if the user taps Send too early. Export failures show a message and leave the original video untouched.

## Build plumbing

`ci/prepare.py` applies four port patches and copies `native/VGMediaConversion.inc` to `submodules/LegacyComponents/Sources/VGMediaConversion.h` in the pinned Telegram-iOS checkout, where it is included by the original gallery implementation. The BUILD patch links AVFoundation and Photos.

`submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift` constructs the actual `TelegramMediaFileAttribute.Audio(isVoice: true)` or `Video(flags: [.instantRoundVideo, .supportsStreaming])`, with `isFile=false` for converted media. This is important: merely sending an MP4/M4A with a filename does not make Telegram render a genuine round-video or voice message.

## Verification gates before releasing

1. Run `python3 -m unittest discover -s ci/tests` and `python3 ci/prepare.py telegram` against the pinned upstream commit.
2. Compile the native iOS port via the repository's existing **Native iOS port** workflow.
3. Sign the resulting unsigned IPA separately and test on an iPhone.
4. In a private test chat, send normal video, converted voice, and converted round note. Confirm on a **second** Telegram client that converted messages render as voice and round video, not as ordinary files. Check iCloud assets, portrait/landscape rotation, trim ranges, no-audio input, 60-second cap, cancel/retry, and multiple selections.
5. Confirm the circular crop position and zoom match the final video on device.

**Status:** source changes are committed on a separate feature branch. No IPA-building workflow was started. Successful compilation and real-device behavior remain unverified until approval to run the build.
