import Foundation
import UIKit
import AVFoundation
import ImageIO
import SGSimpleSettings

public final class AyuGramBackdropView: UIView {
    public typealias Scope = AyuGramAppearanceScope
    private let scope: Scope
    private let imageView = UIImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let dimView = UIView()
    private let rowTintView = UIView()
    private var renderer: AyuGramSilentVideoRenderer?
    private var videoTransform = CGAffineTransform.identity
    private var videoReady = false
    private var imageGenerator: AVAssetImageGenerator?
    private var url: URL?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    public var visibilityChanged: ((Bool) -> Void)?
    /// Chat list rows are drawn transparent over the custom media; this tint
    /// (row colour at the chosen row opacity) covers the whole screen so the
    /// header area and the rows share one shade.
    public var rowTint: UIColor? {
        didSet { applyRowTint(AyuGramAppearance.shared.effectiveSettings(for: scope)) }
    }
    public var overlayColor: UIColor = .systemBackground {
        didSet { dimView.backgroundColor = overlayColor.withAlphaComponent(CGFloat(AyuGramAppearance.shared.effectiveSettings(for: scope).dim)) }
    }
    public init(scope: Scope) {
        self.scope = scope
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        addSubview(blurView)
        addSubview(dimView)
        addSubview(rowTintView)
        for name in [AyuGramAppearance.didChange, UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification, Notification.Name.NSProcessInfoPowerStateDidChange, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        imageGenerator?.cancelAllCGImageGeneration()
        renderer?.stop()
    }
    public func reload() {
        let settings = AyuGramAppearance.shared.effectiveSettings(for: scope)
        let enabled = scope == .chatList ? settings.chatList : settings.conversations
        let nextURL = enabled ? AyuGramAppearance.shared.mediaURL(for: scope) : nil
        isHidden = nextURL == nil
        if url != nextURL {
            generation += 1
            url = nextURL
            imageGenerator?.cancelAllCGImageGeneration()
            imageGenerator = nil
            renderer?.stop()
            renderer?.layer.removeFromSuperlayer()
            renderer = nil
            videoReady = false
            videoTransform = .identity
            imageView.image = nil
            if let nextURL {
                loadImage(nextURL, video: settings.isVideo)
                if settings.isVideo {
                    let generation = self.generation
                    let asset = AVURLAsset(url: nextURL)
                    asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
                        guard let track = asset.tracks(withMediaType: .video).first else { return }
                        let transform = track.preferredTransform
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.url == nextURL, self.generation == generation else { return }
                            let renderer = AyuGramSilentVideoRenderer(url: nextURL)
                            renderer.layer.isHidden = true
                            renderer.firstFrameDisplayed = { [weak self, weak renderer] in
                                guard let self, let renderer, self.renderer === renderer else { return }
                                self.videoReady = true
                                self.updatePlayback()
                            }
                            self.videoTransform = transform
                            self.layer.insertSublayer(renderer.layer, at: 0)
                            self.renderer = renderer
                            self.setNeedsLayout()
                            self.updatePlayback()
                        }
                    }
                }
            }
        }
        blurView.alpha = CGFloat(settings.blur)
        dimView.backgroundColor = overlayColor.withAlphaComponent(CGFloat(settings.dim))
        applyRowTint(settings)
        updatePlayback()
        visibilityChanged?(nextURL != nil)
    }
    private func applyRowTint(_ settings: AyuGramAppearanceSettings) {
        rowTintView.backgroundColor = rowTint?.withAlphaComponent(CGFloat(settings.rowOpacity))
        rowTintView.isHidden = rowTint == nil
    }
    private func loadImage(_ url: URL, video: Bool) {
        let generation = self.generation
        if video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1536, height: 1536)
            imageGenerator = generator
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { [weak self] _, image, _, result, _ in
                let thumbnail = result == .succeeded ? image.map { UIImage(cgImage: $0) } : nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.url == url, self.generation == generation else { return }
                    self.imageView.image = thumbnail
                    self.imageGenerator = nil
                    self.updatePlayback()
                }
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image: UIImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [String: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                    kCGImageSourceCreateThumbnailWithTransform as String: true,
                    kCGImageSourceThumbnailMaxPixelSize as String: 1536,
                    kCGImageSourceShouldCacheImmediately as String: true
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
            } else { image = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.url == url, self.generation == generation else { return }
                self.imageView.image = image
                self.updatePlayback()
            }
        }
    }
    private func updatePlayback() {
        let settings = AyuGramAppearance.shared.effectiveSettings(for: scope)
        let playing = window != nil && !isHidden && UIApplication.shared.applicationState == .active && settings.animateVideo && !ProcessInfo.processInfo.isLowPowerModeEnabled && !UIAccessibility.isReduceMotionEnabled
        if playing { renderer?.start() } else { renderer?.stop() }
        if let videoLayer = renderer?.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.isHidden = !settings.isVideo || !playing || !videoReady
            CATransaction.commit()
        }
        imageView.isHidden = settings.isVideo && playing && videoReady
    }
    public override func didMoveToWindow() { super.didMoveToWindow(); updatePlayback() }
    public override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        blurView.frame = bounds
        dimView.frame = bounds
        rowTintView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let videoLayer = renderer?.layer {
            // Sample buffer layers ignore the track orientation; apply its quarter turns.
            let angle = atan2(videoTransform.b, videoTransform.a)
            let quarterTurns = Int((angle / (.pi / 2.0)).rounded()) & 3
            let size = quarterTurns % 2 == 1 ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
            videoLayer.setAffineTransform(.identity)
            videoLayer.bounds = CGRect(origin: .zero, size: size)
            videoLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            videoLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(quarterTurns) * .pi / 2.0))
        }
        CATransaction.commit()
    }
}
