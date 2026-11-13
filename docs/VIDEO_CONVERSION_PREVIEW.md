# Native video preview conversion (feature branch)

This feature is integrated into the **source-built VoidGram iOS app**, not a
separately injected tweak. **The IPA build must not be triggered or merged into
`main` until the owner authorizes it.**

## UI

While a video is the focused item in Telegram's gallery preview, show two
small buttons on the upper trailing side:

- **Video Note** (`video.circle.fill`): open a full-screen circular crop editor.
  Drag to position the crop and pinch to zoom; Reset restores the center crop.
  The round message is sent only after the user taps **اعتماد وإرسال**.
- **Video → Voice** (`waveform`): extract the video's audio and send an
  actual Ogg/Opus voice message, using the existing `AyuAudioToVoice` sender.

Photo previews show neither control. Ordinary gallery Send remains unchanged.
The UI is added via `LegacyMediaPickerGallery.swift` after all VoidGram patches.

## Video note encoding

The crop editor stores a normalized square relative to the *display-oriented*
video. `AyuVideoCircle.convert` applies the video's preferred transform,
moves the selected crop into the render origin, and exports a 640 x 640 MP4.
The outgoing `TelegramMediaFile` includes `Video` with `instantRoundVideo`
and `supportsStreaming` attributes. The existing 60-second video-note cap
is preserved.

The selected video is copied or exported from the Photos library to a
temporary local file before either conversion. The existing TelegramUI
conversion/sending code is reused, not duplicated in MediaPickerUI.

## Source layout

- `port_overlays/AyuVideoPreviewActions.swift`: preview buttons, Photos
  file preparation and native circular pan/zoom interface.
- `port_overlays/AyuMediaConversionBridge.swift`: TelegramCore bridge
  avoiding MediaPickerUI → TelegramUI circular dependency.
- `ci/video_conversion.py`: pinned-upstream source assembly, exact-anchor
  checks and 640 x 640 encoder adaptation.
- `ci/prepare.py`: invokes the source overlay after all existing patches.
- `ci/tests/test_video_conversion.py`: no-build source assembly tests.

## Verification before publishing

1. Run the Python tests and confirm all overlay anchors are present.
2. With **owner approval**, run the native IPA workflow on a branch that includes
   these changes and resolve any compiler errors.
3. Install a signed test IPA and check photo/video focus transitions, both
   buttons, cancellation, reset, pinch/pan, portrait/landscape sources and clips
   longer than 60 seconds.
4. On the recipient side, confirm Video Note appears as a *round video message*
   (not a file) and video-to-voice appears with the waveform/voice UI (not a
   generic file or a video). Verify audio, duration, retention, download size,
   multi-account sending and a video stored in iCloud.
5. Verify the existing editor, media captions, scheduled/silent sends and
   unaffected attachment actions still work.

No claim of on-device verification is made before the owner's approved build
and test. Existing Telegram-iOS signing/API credentials are still required.
