import Foundation
import UIKit
import AVFoundation
import ImageIO

public final class AyuGramProfileMediaView: UIView {
    private let imageView = UIImageView()
    private let shadeLayer = CAGradientLayer()
    private var renderer: AyuGramSilentVideoRenderer?
    private var videoTransform = CGAffineTransform.identity
    private var videoReady = false
    private var imageGenerator: AVAssetImageGenerator?
    private var url: URL?
    private var isVideo = false
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    public var isActive: Bool = true {
        didSet {
            if self.isActive != oldValue {
                self.updatePlayback()
            }
        }
    }

    public var hasMedia: Bool {
        return self.url != nil
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.addSubview(self.imageView)
        self.shadeLayer.colors = [
            UIColor(white: 0.0, alpha: 0.5).cgColor,
            UIColor(white: 0.0, alpha: 0.12).cgColor,
            UIColor(white: 0.0, alpha: 0.28).cgColor,
            UIColor(white: 0.0, alpha: 0.72).cgColor
        ]
        self.shadeLayer.locations = [0.0, 0.3, 0.6, 1.0]
        self.shadeLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.shadeLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.layer.addSublayer(self.shadeLayer)
        let names: [Notification.Name] = [
            UIApplication.didBecomeActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            UIAccessibility.reduceMotionStatusDidChangeNotification
        ]
        for name in names {
            self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.updatePlayback()
            }))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.imageGenerator?.cancelAllCGImageGeneration()
        self.renderer?.stop()
    }

    public func setMedia(url: URL?, isVideo: Bool) {
        if self.url == url && self.isVideo == isVideo {
            return
        }
        self.generation += 1
        self.url = url
        self.isVideo = isVideo
        self.imageGenerator?.cancelAllCGImageGeneration()
        self.imageGenerator = nil
        self.renderer?.stop()
        self.renderer?.layer.removeFromSuperlayer()
        self.renderer = nil
        self.videoReady = false
        self.videoTransform = .identity
        self.imageView.image = nil
        guard let url else {
            self.updatePlayback()
            return
        }
        let generation = self.generation
        if isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280.0, height: 1280.0)
            self.imageGenerator = generator
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)], completionHandler: { [weak self] _, image, _, result, _ in
                let poster = result == .succeeded ? image.map { UIImage(cgImage: $0) } : nil
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else {
                        return
                    }
                    self.imageView.image = poster
                    self.imageGenerator = nil
                    self.updatePlayback()
                }
            })
            let asset = AVURLAsset(url: url)
            asset.loadValuesAsynchronously(forKeys: ["tracks"], completionHandler: { [weak self] in
                guard let track = asset.tracks(withMediaType: .video).first else {
                    return
                }
                let transform = track.preferredTransform
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else {
                        return
                    }
                    let renderer = AyuGramSilentVideoRenderer(url: url)
                    renderer.layer.isHidden = true
                    renderer.firstFrameDisplayed = { [weak self, weak renderer] in
                        guard let self, let renderer, self.renderer === renderer else {
                            return
                        }
                        self.videoReady = true
                        self.updatePlayback()
                    }
                    self.videoTransform = transform
                    self.layer.insertSublayer(renderer.layer, at: 0)
                    self.renderer = renderer
                    self.setNeedsLayout()
                    self.updatePlayback()
                }
            })
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var image: UIImage?
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    let options: [String: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                        kCGImageSourceCreateThumbnailWithTransform as String: true,
                        kCGImageSourceThumbnailMaxPixelSize as String: 1600,
                        kCGImageSourceShouldCacheImmediately as String: true
                    ]
                    image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
                }
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else {
                        return
                    }
                    self.imageView.image = image
                    self.updatePlayback()
                }
            }
        }
        self.updatePlayback()
    }

    private func updatePlayback() {
        let playing = self.isVideo && self.isActive && self.window != nil && !self.isHidden && UIApplication.shared.applicationState == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled && !UIAccessibility.isReduceMotionEnabled
        if playing {
            self.renderer?.start()
        } else {
            self.renderer?.stop()
        }
        if let videoLayer = self.renderer?.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.isHidden = !playing || !self.videoReady
            CATransaction.commit()
        }
        self.imageView.isHidden = playing && self.videoReady
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updatePlayback()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.shadeLayer.frame = self.bounds
        if let videoLayer = self.renderer?.layer {
            let angle = atan2(self.videoTransform.b, self.videoTransform.a)
            let quarterTurns = Int((angle / (.pi / 2.0)).rounded()) & 3
            let size = quarterTurns % 2 == 1 ? CGSize(width: self.bounds.height, height: self.bounds.width) : self.bounds.size
            videoLayer.setAffineTransform(.identity)
            videoLayer.bounds = CGRect(origin: .zero, size: size)
            videoLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            videoLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(quarterTurns) * .pi / 2.0))
        }
        CATransaction.commit()
    }
}
