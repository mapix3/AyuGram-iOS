import Foundation
import UIKit
import AVFoundation
import Photos
import Display
import AccountContext
import TelegramPresentationData
import SGStrings

public struct AyuGramRoundVideoSelection {
    public let asset: PHAsset
    public let dimensions: CGSize
    public let cropRect: CGRect
    public let start: Double
    public let duration: Double
    public let thumbnail: UIImage?
}

private final class AyuGramRoundPlayerView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        return self.layer as! AVPlayerLayer
    }
}

private func ayuRoundTimeString(_ value: Double) -> String {
    let total = max(0, Int(value.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

final class AyuGramRoundVideoEditorView: UIView {
    private let asset: PHAsset
    private let locale: String
    private let theme: PresentationTheme
    private let videoSize: CGSize
    private let maximumLength: Double = 60.0
    private let minimumLength: Double = 1.0

    private let stage = UIView()
    private let playerView = AyuGramRoundPlayerView()
    private let ring = CAShapeLayer()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let hintLabel = UILabel()
    private let startTitle = UILabel()
    private let startValue = UILabel()
    private let startSlider = UISlider()
    private let lengthTitle = UILabel()
    private let lengthValue = UILabel()
    private let lengthSlider = UISlider()

    private var player: AVPlayer?
    private var avAsset: AVAsset?
    private var timeObserver: Any?
    private var duration: Double = 0.0
    private var start: Double = 0.0
    private var length: Double = 0.0
    private var zoom: CGFloat = 1.0
    private var offset: CGPoint = .zero
    private var gestureZoom: CGFloat = 1.0
    private var gestureOffset: CGPoint = .zero
    private var stageSide: CGFloat = 0.0
    private var requestId: PHImageRequestID?

    var readyChanged: ((Bool) -> Void)?

    var isReady: Bool {
        return self.avAsset != nil && self.length >= self.minimumLength
    }

    init(asset: PHAsset, theme: PresentationTheme, locale: String) {
        self.asset = asset
        self.theme = theme
        self.locale = locale
        self.videoSize = CGSize(width: max(1, asset.pixelWidth), height: max(1, asset.pixelHeight))
        super.init(frame: CGRect())

        self.backgroundColor = .black

        self.stage.clipsToBounds = true
        self.stage.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.addSubview(self.stage)
        self.playerView.playerLayer.videoGravity = .resizeAspectFill
        self.playerView.isUserInteractionEnabled = false
        self.stage.addSubview(self.playerView)

        self.ring.fillColor = UIColor.clear.cgColor
        self.ring.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        self.ring.lineWidth = 2.0
        self.layer.addSublayer(self.ring)

        self.spinner.color = .white
        self.spinner.startAnimating()
        self.addSubview(self.spinner)

        self.hintLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.hintLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.hintLabel.textAlignment = .center
        self.hintLabel.numberOfLines = 0
        self.hintLabel.text = i18n("Ayu.RoundEditor.Hint", locale)
        self.addSubview(self.hintLabel)

        for label in [self.startTitle, self.lengthTitle] {
            label.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
            label.textColor = .white
            self.addSubview(label)
        }
        for label in [self.startValue, self.lengthValue] {
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 15.0, weight: .regular)
            label.textColor = UIColor(white: 1.0, alpha: 0.7)
            label.textAlignment = .right
            self.addSubview(label)
        }
        self.startTitle.text = i18n("Ayu.RoundEditor.Start", locale)
        self.lengthTitle.text = i18n("Ayu.RoundEditor.Length", locale)

        for slider in [self.startSlider, self.lengthSlider] {
            slider.minimumTrackTintColor = theme.list.itemAccentColor
            slider.isEnabled = false
            self.addSubview(slider)
        }
        self.startSlider.addTarget(self, action: #selector(self.startChanged), for: .valueChanged)
        self.lengthSlider.addTarget(self, action: #selector(self.lengthChanged), for: .valueChanged)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.handlePinch(_:)))
        self.stage.addGestureRecognizer(pan)
        self.stage.addGestureRecognizer(pinch)

        self.load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let requestId = self.requestId {
            PHImageManager.default().cancelImageRequest(requestId)
        }
        if let timeObserver = self.timeObserver {
            self.player?.removeTimeObserver(timeObserver)
        }
        self.player?.pause()
    }

    private func load() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        self.requestId = PHImageManager.default().requestAVAsset(forVideo: self.asset, options: options, resultHandler: { [weak self] avAsset, _, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.requestId = nil
                guard let avAsset else {
                    self.spinner.stopAnimating()
                    self.hintLabel.text = i18n("Ayu.RoundEditor.Failed", self.locale)
                    self.setNeedsLayout()
                    return
                }
                self.setup(avAsset: avAsset)
            }
        })
    }

    private func setup(avAsset: AVAsset) {
        self.avAsset = avAsset
        let assetDuration = avAsset.duration.seconds
        self.duration = assetDuration.isFinite && assetDuration > 0.0 ? assetDuration : self.asset.duration
        self.length = min(self.maximumLength, self.duration)
        self.start = 0.0

        let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
        player.actionAtItemEnd = .none
        self.player = player
        self.playerView.playerLayer.player = player
        self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main, using: { [weak self] time in
            guard let self else {
                return
            }
            if time.seconds >= self.start + self.length - 0.02 || time.seconds < self.start - 0.5 {
                self.seekToStart()
            }
        })
        player.play()

        self.spinner.stopAnimating()
        self.startSlider.isEnabled = self.duration > self.minimumLength
        self.lengthSlider.isEnabled = self.duration > self.minimumLength
        self.updateSliders()
        self.readyChanged?(self.isReady)
        self.setNeedsLayout()
    }

    private func seekToStart() {
        self.player?.seek(to: CMTime(seconds: self.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600))
        self.player?.play()
    }

    private func updateSliders() {
        let maximumLength = min(self.maximumLength, self.duration)
        self.lengthSlider.minimumValue = Float(min(self.minimumLength, maximumLength))
        self.lengthSlider.maximumValue = Float(maximumLength)
        self.lengthSlider.value = Float(self.length)
        let maximumStart = max(0.0, self.duration - self.length)
        self.startSlider.minimumValue = 0.0
        self.startSlider.maximumValue = Float(maximumStart)
        self.startSlider.value = Float(min(self.start, maximumStart))
        self.startSlider.isEnabled = maximumStart > 0.05
        self.startValue.text = ayuRoundTimeString(self.start) + " – " + ayuRoundTimeString(self.start + self.length)
        self.lengthValue.text = String(format: "%.1f s", self.length)
    }

    @objc private func startChanged() {
        self.start = Double(self.startSlider.value)
        self.updateSliders()
        self.seekToStart()
    }

    @objc private func lengthChanged() {
        self.length = max(self.minimumLength, min(self.maximumLength, Double(self.lengthSlider.value)))
        if self.start + self.length > self.duration {
            self.start = max(0.0, self.duration - self.length)
        }
        self.updateSliders()
        self.readyChanged?(self.isReady)
    }

    private func coverScale(side: CGFloat) -> CGFloat {
        return max(side / self.videoSize.width, side / self.videoSize.height)
    }

    private func clampedOffset(_ offset: CGPoint, zoom: CGFloat) -> CGPoint {
        let side = self.stageSide
        guard side > 0.0 else {
            return .zero
        }
        let scale = self.coverScale(side: side) * zoom
        let limitX = max(0.0, (self.videoSize.width * scale - side) / 2.0)
        let limitY = max(0.0, (self.videoSize.height * scale - side) / 2.0)
        return CGPoint(x: max(-limitX, min(limitX, offset.x)), y: max(-limitY, min(limitY, offset.y)))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.gestureOffset = self.offset
        case .changed:
            let translation = recognizer.translation(in: self.stage)
            self.offset = self.clampedOffset(CGPoint(x: self.gestureOffset.x + translation.x, y: self.gestureOffset.y + translation.y), zoom: self.zoom)
            self.layoutVideo()
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.gestureZoom = self.zoom
        case .changed:
            self.zoom = max(1.0, min(5.0, self.gestureZoom * recognizer.scale))
            self.offset = self.clampedOffset(self.offset, zoom: self.zoom)
            self.layoutVideo()
        default:
            break
        }
    }

    private func layoutVideo() {
        let side = self.stageSide
        guard side > 0.0 else {
            return
        }
        let scale = self.coverScale(side: side) * self.zoom
        let size = CGSize(width: self.videoSize.width * scale, height: self.videoSize.height * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.playerView.frame = CGRect(x: (side - size.width) / 2.0 + self.offset.x, y: (side - size.height) / 2.0 + self.offset.y, width: size.width, height: size.height)
        CATransaction.commit()
    }

    var normalizedCrop: CGRect {
        let side = self.stageSide
        guard side > 0.0 else {
            let minSide = min(self.videoSize.width, self.videoSize.height)
            return CGRect(x: (self.videoSize.width - minSide) / 2.0 / self.videoSize.width, y: (self.videoSize.height - minSide) / 2.0 / self.videoSize.height, width: minSide / self.videoSize.width, height: minSide / self.videoSize.height)
        }
        let frame = self.playerView.frame
        let x = max(0.0, min(1.0, -frame.minX / frame.width))
        let y = max(0.0, min(1.0, -frame.minY / frame.height))
        let width = max(0.0, min(1.0 - x, side / frame.width))
        let height = max(0.0, min(1.0 - y, side / frame.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func makeSelection(completion: @escaping (AyuGramRoundVideoSelection?) -> Void) {
        guard let avAsset = self.avAsset, self.isReady else {
            completion(nil)
            return
        }
        self.player?.pause()
        let normalized = self.normalizedCrop
        let pixelSide = floor(min(normalized.width * self.videoSize.width, normalized.height * self.videoSize.height))
        let cropRect = CGRect(x: floor(normalized.minX * self.videoSize.width), y: floor(normalized.minY * self.videoSize.height), width: pixelSide, height: pixelSide)
        let start = self.start
        let length = self.length
        let asset = self.asset
        let dimensions = self.videoSize
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280.0, height: 1280.0)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: start, preferredTimescale: 600))], completionHandler: { _, image, _, _, _ in
            var thumbnail: UIImage?
            if let image {
                let width = CGFloat(image.width)
                let height = CGFloat(image.height)
                let side = floor(min(normalized.width * width, normalized.height * height))
                let rect = CGRect(x: floor(normalized.minX * width), y: floor(normalized.minY * height), width: side, height: side)
                if side >= 1.0, let cropped = image.cropping(to: rect) {
                    thumbnail = UIImage(cgImage: cropped)
                }
            }
            DispatchQueue.main.async {
                completion(AyuGramRoundVideoSelection(asset: asset, dimensions: dimensions, cropRect: cropRect, start: start, duration: length, thumbnail: thumbnail))
            }
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        let inset: CGFloat = 24.0
        let side = floor(min(width - inset * 2.0, self.bounds.height * 0.55))
        let stageFrame = CGRect(x: floor((width - side) / 2.0), y: 24.0, width: side, height: side)
        let sideChanged = abs(side - self.stageSide) > 0.5
        self.stage.frame = stageFrame
        self.stage.layer.cornerRadius = side / 2.0
        self.stageSide = side
        if sideChanged {
            self.offset = self.clampedOffset(self.offset, zoom: self.zoom)
        }
        self.layoutVideo()
        self.ring.frame = stageFrame
        self.ring.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: stageFrame.size).insetBy(dx: 1.0, dy: 1.0)).cgPath
        self.spinner.center = CGPoint(x: stageFrame.midX, y: stageFrame.midY)

        var y = stageFrame.maxY + 14.0
        let hintHeight = ceil(self.hintLabel.sizeThatFits(CGSize(width: width - inset * 2.0, height: 200.0)).height)
        self.hintLabel.frame = CGRect(x: inset, y: y, width: width - inset * 2.0, height: hintHeight)
        y += hintHeight + 22.0

        for (title, value, slider) in [(self.startTitle, self.startValue, self.startSlider), (self.lengthTitle, self.lengthValue, self.lengthSlider)] {
            title.frame = CGRect(x: inset, y: y, width: (width - inset * 2.0) / 2.0, height: 20.0)
            value.frame = CGRect(x: width / 2.0, y: y, width: width / 2.0 - inset, height: 20.0)
            y += 26.0
            slider.frame = CGRect(x: inset, y: y, width: width - inset * 2.0, height: 32.0)
            y += 46.0
        }
    }
}

private final class AyuGramRoundVideoEditorController: AyuGramHostController {
    private let editor: AyuGramRoundVideoEditorView
    private let completion: (AyuGramRoundVideoSelection) -> Void
    private var isSending = false

    init(context: AccountContext, asset: PHAsset, completion: @escaping (AyuGramRoundVideoSelection) -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let locale = presentationData.strings.baseLanguageCode
        let editor = AyuGramRoundVideoEditorView(asset: asset, theme: presentationData.theme, locale: locale)
        self.editor = editor
        self.completion = completion
        super.init(context: context, title: i18n("Ayu.RoundEditor.Title", locale), content: editor)
        let sendItem = UIBarButtonItem(title: i18n("Ayu.RoundEditor.Send", locale), style: .done, target: self, action: #selector(self.sendPressed))
        sendItem.isEnabled = false
        self.navigationItem.rightBarButtonItem = sendItem
        editor.readyChanged = { [weak sendItem] ready in
            sendItem?.isEnabled = ready
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sendPressed() {
        guard !self.isSending, self.editor.isReady else {
            return
        }
        self.isSending = true
        self.navigationItem.rightBarButtonItem?.isEnabled = false
        self.editor.makeSelection(completion: { [weak self] selection in
            guard let self else {
                return
            }
            guard let selection else {
                self.isSending = false
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                return
            }
            self.completion(selection)
            if let navigationController = self.navigationController as? NavigationController {
                navigationController.filterController(self, animated: true)
            } else {
                self.dismiss()
            }
        })
    }
}

public func ayuGramRoundVideoEditorController(context: AccountContext, asset: PHAsset, completion: @escaping (AyuGramRoundVideoSelection) -> Void) -> ViewController {
    return AyuGramRoundVideoEditorController(context: context, asset: asset, completion: completion)
}
