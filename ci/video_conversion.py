"""Apply native, non-dylib video-to-voice and video-to-note preview integration.

Called by prepare.py AFTER the pinned Telegram source has had all VoidGram
patches applied. Each text anchor is asserted once so an upstream change fails
loudly instead of silently shipping a build without the controls.
"""
from pathlib import Path
import shutil


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: required video conversion anchor occurs {count} times")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def integrate_video_circle(source: Path) -> None:
    path = source / "submodules/TelegramUI/Sources/AyuVideoCircle.swift"
    text = path.read_text(encoding="utf-8")
    start_marker = "    static func convert(path: String, completion: @escaping (URL?, Double) -> Void) {"
    end_marker = "    static func send(path: String, to chat: ChatControllerImpl) {"
    if text.count(start_marker) != 1 or text.count(end_marker) != 1:
        raise RuntimeError("VideoCircle conversion implementation has changed")
    start = text.index(start_marker)
    end = text.index(end_marker)
    replacement = """    /// Video message encoder. Pixel crop matches the square selected by the
    /// user in the native preview, including track rotation and pinch zoom.
    static func convert(path: String, crop: AyuMediaVideoCrop? = nil,
                        completion: @escaping (URL?, Double) -> Void) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let track = asset.tracks(withMediaType: .video).first else {
            completion(nil, 0.0)
            return
        }
        let oriented = CGRect(origin: .zero, size: track.naturalSize)
            .applying(track.preferredTransform)
        let width = abs(oriented.width)
        let height = abs(oriented.height)
        let centerSide = min(width, height)
        let duration = min(60.0, CMTimeGetSeconds(asset.duration))
        guard width.isFinite, height.isFinite, centerSide > 0,
              duration.isFinite, duration > 0 else {
            completion(nil, 0.0)
            return
        }

        let defaultSquare = CGRect(
            x: (width - centerSide) / 2.0, y: (height - centerSide) / 2.0,
            width: centerSide, height: centerSide)
        var square = defaultSquare
        if let crop {
            // The preview's normalized crop rect is measured in the
            // display-oriented video, not the unrotated track coordinates.
            let requested = CGRect(
                x: crop.x * width, y: crop.y * height,
                width: crop.width * width, height: crop.height * height)
            let side = min(requested.width, requested.height)
            if side.isFinite && side >= 1.0 &&
               requested.origin.x.isFinite && requested.origin.y.isFinite {
                square = CGRect(
                    x: max(0.0, min(width - side, requested.midX - side / 2.0)),
                    y: max(0.0, min(height - side, requested.midY - side / 2.0)),
                    width: side, height: side)
            }
        }

        let output: CGFloat = 640.0
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: output, height: output)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // Normalize preferredTransform's image bounds, pan to the selected
        // square and scale that square to a real 640×640 H.264 MP4.
        let transform = track.preferredTransform
            .concatenating(CGAffineTransform(
                translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(
                translationX: -square.minX, y: -square.minY))
            .concatenating(CGAffineTransform(
                scaleX: output / square.width, y: output / square.height))
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil, 0.0)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ayu_circle_\\(UUID().uuidString).mp4")
        export.outputURL = url
        export.outputFileType = .mp4
        export.videoComposition = composition
        export.timeRange = instruction.timeRange
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            DispatchQueue.main.async {
                completion(export.status == .completed ? url : nil, duration)
            }
        }
    }

"""
    text = text[:start] + replacement + text[end:]
    text = text.replace(end_marker, "    static func send(path: String, to chat: ChatControllerImpl, crop: AyuMediaVideoCrop? = nil) {", 1)
    original_call = "        convert(path: path, completion: { [weak chat] url, duration in"
    if text.count(original_call) != 1:
        raise RuntimeError("VideoCircle send call site has changed")
    text = text.replace(original_call,
                        "        convert(path: path, crop: crop, completion: { [weak chat] url, duration in", 1)
    original_size = "PixelDimensions(width: 384, height: 384)"
    if text.count(original_size) != 1:
        raise RuntimeError("VideoCircle video attribute size changed")
    text = text.replace(original_size, "PixelDimensions(width: 640, height: 640)")
    path.write_text(text, encoding="utf-8")


def apply(source: Path, port_root: Path) -> None:
    copies = (
        ("port_overlays/AyuMediaConversionBridge.swift",
         "submodules/TelegramCore/Sources/AyuGram/AyuMediaConversionBridge.swift"),
        ("port_overlays/AyuVideoPreviewActions.swift",
         "submodules/MediaPickerUI/Sources/AyuVideoPreviewActions.swift"),
    )
    for from_path, to_path in copies:
        target = source / to_path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(port_root / from_path, target)

    # MediaPickerUI cannot depend on TelegramUI, so pass the converted file to
    # the active chat via the shared TelegramCore bridge. No private TL patches.
    chat = source / "submodules/TelegramUI/Sources/ChatController.swift"
    replace_once(
        chat,
        "            AyuPluginChatTracker.current = self\n",
        """            AyuPluginChatTracker.current = self
            AyuMediaConversionBridge.send = { [weak self] path, kind, crop in
                guard let chat = self else { return }
                switch kind {
                case .voice:
                    AyuAudioToVoice.send(path: path, to: chat)
                case .roundVideo:
                    AyuVideoCircle.send(path: path, to: chat, crop: crop)
                }
            }
""")

    gallery = source / "submodules/MediaPickerUI/Sources/LegacyMediaPickerGallery.swift"
    replace_once(
        gallery,
        "    var transitionedIn = false\n    controller.itemFocused = { item in\n",
        """    // Native, always-visible media conversion buttons in a video preview.
    // Their positions follow the gallery's safe area during rotation.
    let ayuVideoActions = AyuVideoPreviewActions(frame: .zero)
    controller.view.addSubview(ayuVideoActions)
    NSLayoutConstraint.activate([
        ayuVideoActions.trailingAnchor.constraint(
            equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -12.0),
        ayuVideoActions.topAnchor.constraint(
            equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 78.0)
    ])
    ayuVideoActions.update(item: focusItem)
    ayuVideoActions.onAction = { [weak controller, weak ayuVideoActions] kind, asset in
        guard let controller = controller else { return }
        ayuVideoActions?.isUserInteractionEnabled = false
        AyuVideoPickerExporter.prepare(asset: asset) { [weak controller, weak ayuVideoActions] url in
            ayuVideoActions?.isUserInteractionEnabled = true
            guard let controller = controller else { return }
            guard let url = url else {
                let alert = UIAlertController(
                    title: "تعذر تجهيز الفيديو",
                    message: "تحقق من توفر الفيديو في الصور وأعد المحاولة.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "حسناً", style: .default))
                controller.present(alert, animated: true)
                return
            }
            let finish: (AyuMediaVideoCrop?) -> Void = { crop in
                guard let send = AyuMediaConversionBridge.send else {
                    let alert = UIAlertController(
                        title: "تعذر تحديد المحادثة",
                        message: "افتح الفيديو من محادثة تيليجرام وحاول مجدداً.",
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "حسناً", style: .default))
                    controller.present(alert, animated: true)
                    return
                }
                send(url.path, kind, crop)
                controller.dismissWhenReady(animated: true)
                dismissAll()
            }
            switch kind {
            case .voice:
                finish(nil)
            case .roundVideo:
                let cropController = AyuVideoRoundCropController(
                    url: url, onApply: { crop in finish(crop) })
                controller.present(cropController, animated: true)
            }
        }
    }

    var transitionedIn = false
    controller.itemFocused = { item in
        ayuVideoActions.update(item: item)
""")

    integrate_video_circle(source)
    print("Integrated native video note crop + video-to-voice preview actions")
