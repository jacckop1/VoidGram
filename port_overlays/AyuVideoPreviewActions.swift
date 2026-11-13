import Foundation
import UIKit
import Photos
import AVFoundation
import LegacyComponents
import TelegramCore

/// Two native actions shown only while a video is focused in the Telegram
/// media gallery. This is compiled into MediaPickerUI, not injected as a dylib.
final class AyuVideoPreviewActions: UIStackView {
    var onAction: ((AyuMediaConversionKind, PHAsset) -> Void)?
    private var focusedAsset: PHAsset?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 10.0
        alignment = .fill
        distribution = .fillEqually
        isHidden = true
        accessibilityIdentifier = "voidgram.videoConversionActions"

        let round = makeButton(symbol: "video.circle.fill", label: "فيديو نوت · تحديد القص")
        round.accessibilityIdentifier = "voidgram.videoToNote"
        round.addTarget(self, action: #selector(roundPressed), for: .touchUpInside)
        addArrangedSubview(round)

        let voice = makeButton(symbol: "waveform", label: "تحويل الفيديو إلى فويس")
        voice.accessibilityIdentifier = "voidgram.videoToVoice"
        voice.addTarget(self, action: #selector(voicePressed), for: .touchUpInside)
        addArrangedSubview(voice)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 50.0),
            heightAnchor.constraint(equalToConstant: 110.0)
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeButton(symbol: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        button.tintColor = .white
        button.layer.cornerRadius = 25.0
        button.clipsToBounds = true
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityLabel = label
        button.accessibilityTraits = .button
        return button
    }

    func update(item: TGModernGalleryItem?) {
        focusedAsset = nil
        if let item = item as? TGMediaPickerGalleryItem {
            if let asset = item.asset as? TGMediaAsset, asset.isVideo {
                focusedAsset = asset.backingAsset
            } else if let cameraVideo = item.asset as? TGCameraCapturedVideo,
                      let asset = cameraVideo.originalAsset {
                focusedAsset = asset.backingAsset
            }
        }
        isHidden = focusedAsset == nil
    }

    @objc private func roundPressed() {
        if let asset = focusedAsset {
            onAction?(.roundVideo, asset)
        }
    }

    @objc private func voicePressed() {
        if let asset = focusedAsset {
            onAction?(.voice, asset)
        }
    }
}

/// Obtain a local file URL even when Photos supplies an AVComposition instead
/// of an AVURLAsset. The file remains in tmp until Telegram finishes uploading.
enum AyuVideoPickerExporter {
    static func prepare(asset: PHAsset, completion: @escaping (URL?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
            guard let video else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if let urlAsset = video as? AVURLAsset, urlAsset.url.isFileURL,
               FileManager.default.isReadableFile(atPath: urlAsset.url.path) {
                let ext = urlAsset.url.pathExtension.isEmpty ? "mov" : urlAsset.url.pathExtension
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent("voidgram_video_\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: urlAsset.url, to: output)
                    DispatchQueue.main.async { completion(output) }
                    return
                } catch {
                    // Some Photos resources are not copyable; export them below.
                }
            }

            guard let session = AVAssetExportSession(asset: video, presetName: AVAssetExportPresetHighestQuality) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let type: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("voidgram_video_\(UUID().uuidString).\(type == .mp4 ? "mp4" : "mov")")
            session.outputURL = output
            session.outputFileType = type
            session.shouldOptimizeForNetworkUse = true
            session.exportAsynchronously {
                DispatchQueue.main.async {
                    completion(session.status == .completed ? output : nil)
                }
            }
        }
    }
}

/// Pre-send circle crop: pan and pinch to place any part of a video inside a
/// true circular preview. Crop parameters are normalized to oriented pixels.
final class AyuVideoRoundCropController: UIViewController, UIScrollViewDelegate {
    var onApply: ((AyuMediaVideoCrop) -> Void)?

    private let videoURL: URL
    private let cropScrollView = UIScrollView()
    private let preview = UIImageView()
    private let confirmButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private var contentIsReady = false

    init(url: URL, onApply: @escaping (AyuMediaVideoCrop) -> Void) {
        self.videoURL = url
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.06, alpha: 1.0)

        let title = UILabel()
        title.text = "تحديد مكان الفيديو نوت"
        title.font = .boldSystemFont(ofSize: 21)
        title.textColor = .white
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let help = UILabel()
        help.text = "حرّك الفيديو داخل الدائرة، وكبّر أو صغّر بإصبعين"
        help.font = .systemFont(ofSize: 14)
        help.textColor = .lightGray
        help.numberOfLines = 2
        help.textAlignment = .center
        help.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(help)

        cropScrollView.backgroundColor = .black
        cropScrollView.clipsToBounds = true
        cropScrollView.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        cropScrollView.layer.borderWidth = 2.0
        cropScrollView.bouncesZoom = true
        cropScrollView.minimumZoomScale = 1.0
        cropScrollView.maximumZoomScale = 5.0
        cropScrollView.showsVerticalScrollIndicator = false
        cropScrollView.showsHorizontalScrollIndicator = false
        cropScrollView.delegate = self
        cropScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cropScrollView)

        preview.contentMode = .scaleToFill
        cropScrollView.addSubview(preview)

        let reset = makeTextButton("إعادة ضبط", tint: .white)
        reset.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        let cancel = makeTextButton("إلغاء", tint: .white)
        cancel.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        confirmButton.setTitle("اعتماد وإرسال", for: .normal)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = .systemBlue
        confirmButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        confirmButton.layer.cornerRadius = 12
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.55
        confirmButton.addTarget(self, action: #selector(applyPressed), for: .touchUpInside)

        let bottom = UIStackView(arrangedSubviews: [cancel, reset, confirmButton])
        bottom.axis = .horizontal
        bottom.alignment = .fill
        bottom.distribution = .fillEqually
        bottom.spacing = 8
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 34),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            help.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            help.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            help.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cropScrollView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            cropScrollView.widthAnchor.constraint(equalToConstant: 296),
            cropScrollView.heightAnchor.constraint(equalTo: cropScrollView.widthAnchor),
            cropScrollView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cropScrollView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -12),
            spinner.centerXAnchor.constraint(equalTo: cropScrollView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: cropScrollView.centerYAnchor),
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            bottom.heightAnchor.constraint(equalToConstant: 50)
        ])
        loadPreview()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cropScrollView.layer.cornerRadius = cropScrollView.bounds.width / 2
        if preview.image != nil && !contentIsReady {
            configureImageFrame()
        }
    }

    private func makeTextButton(_ text: String, tint: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.setTitleColor(tint, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = 12
        return button
    }

    private func loadPreview() {
        let asset = AVURLAsset(url: videoURL)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1400, height: 1400)
            let image = (try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)).map {
                UIImage(cgImage: $0)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.spinner.stopAnimating()
                guard let image else {
                    let alert = UIAlertController(title: "تعذر فتح معاينة الفيديو",
                                                  message: "جرب فيديو آخر.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "حسناً", style: .default))
                    self.present(alert, animated: true)
                    return
                }
                self.preview.image = image
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.confirmButton.isEnabled = true
                self.confirmButton.alpha = 1.0
            }
        }
    }

    private func configureImageFrame() {
        guard let image = preview.image else { return }
        let bounds = cropScrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        preview.frame = CGRect(x: 0, y: 0, width: width, height: height)
        cropScrollView.contentSize = preview.frame.size
        cropScrollView.zoomScale = 1.0
        cropScrollView.contentOffset = CGPoint(x: max(0, (width - bounds.width) / 2),
                                              y: max(0, (height - bounds.height) / 2))
        contentIsReady = true
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return preview
    }

    @objc private func resetPressed() {
        guard contentIsReady else { return }
        cropScrollView.setZoomScale(1.0, animated: false)
        let size = cropScrollView.contentSize
        let bounds = cropScrollView.bounds.size
        cropScrollView.setContentOffset(CGPoint(x: max(0, (size.width - bounds.width) / 2),
                                                y: max(0, (size.height - bounds.height) / 2)),
                                        animated: false)
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func applyPressed() {
        guard contentIsReady else { return }
        let size = cropScrollView.contentSize
        let side = cropScrollView.bounds.width
        guard size.width >= side, size.height >= side else { return }
        let rawX = cropScrollView.contentOffset.x / size.width
        let rawY = cropScrollView.contentOffset.y / size.height
        let w = min(1.0, side / size.width)
        let h = min(1.0, side / size.height)
        let x = max(0.0, min(1.0 - w, rawX))
        let y = max(0.0, min(1.0 - h, rawY))
        let crop = AyuMediaVideoCrop(x: x, y: y, width: w, height: h)
        dismiss(animated: true) { [onApply] in
            onApply(crop)
        }
    }
}
