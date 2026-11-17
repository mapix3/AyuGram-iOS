import Foundation
import UIKit
import Display
import SGSimpleSettings

private final class AyuGramWindowTrackingView: UIView {
    var windowChanged: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isHidden = true
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.windowChanged?()
    }
}

public final class AyuGramWallpaperEffectsController {
    private static let backgroundAmount: CGFloat = 18.0
    private static let patternDepth: CGFloat = 1.6
    private static let auroraDepth: CGFloat = 0.6
    private static let fullTilt: CGFloat = 0.35
    private static let grainMaxOpacity: Float = 0.55

    private static var cachedGrainTile: UIImage?

    private let livePatternBlendUpdated: () -> Void
    private var observer: AyuGramEffectsObserver?
    private var appStateTokens: [NSObjectProtocol] = []
    private var isAppActive = true

    private weak var hostView: UIView?
    private weak var gradientView: UIView?
    private weak var gradientContentView: UIView?
    private weak var patternLayer: CALayer?
    private var colors: [UInt32] = []
    private var size = CGSize()

    private var auroraView: AyuGramAuroraView?
    private var grainLayer: SimpleLayer?
    private var trackingView: AyuGramWindowTrackingView?
    private var tiltListener: Int?
    private var isParallaxApplied = false

    public private(set) var needsLivePatternBlend: Bool

    public init(livePatternBlendUpdated: @escaping () -> Void) {
        self.livePatternBlendUpdated = livePatternBlendUpdated
        self.needsLivePatternBlend = AyuGramWallpaperEffectsController.computeNeedsLivePatternBlend()

        self.observer = AyuGramEffectsRuntime.observe({ [weak self] in
            self?.settingsUpdated()
        })
        let center = NotificationCenter.default
        self.appStateTokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.isAppActive = false
            self.reconcile()
        }))
        self.appStateTokens.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.isAppActive = true
            self.reconcile()
        }))
    }

    deinit {
        for token in self.appStateTokens {
            NotificationCenter.default.removeObserver(token)
        }
        if let tiltListener = self.tiltListener {
            if Thread.isMainThread {
                AyuGramDeviceTilt.shared.removeListener(tiltListener)
            } else {
                DispatchQueue.main.async {
                    AyuGramDeviceTilt.shared.removeListener(tiltListener)
                }
            }
        }
    }

    public func update(hostView: UIView, gradientView: UIView?, gradientContentView: UIView?, patternLayer: CALayer?, colors: [UInt32], size: CGSize) {
        if self.gradientView !== gradientView || self.patternLayer !== patternLayer {
            self.resetParallax()
        }
        self.hostView = hostView
        self.gradientView = gradientView
        self.gradientContentView = gradientContentView
        self.patternLayer = patternLayer
        self.colors = colors
        self.size = size
        self.reconcile()
    }

    private static func computeNeedsLivePatternBlend() -> Bool {
        let settings = AyuGramEffectsRuntime.settings
        return settings.activeAuroraGradient || settings.activeDeepParallax
    }

    private func settingsUpdated() {
        let needsLivePatternBlend = AyuGramWallpaperEffectsController.computeNeedsLivePatternBlend()
        if self.needsLivePatternBlend != needsLivePatternBlend {
            self.needsLivePatternBlend = needsLivePatternBlend
            self.livePatternBlendUpdated()
        }
        self.reconcile()
    }

    private func reconcile() {
        let settings = AyuGramEffectsRuntime.settings
        let continuousAllowed = AyuGramEffectsRuntime.continuousEffectsAllowed && self.isAppActive
        let hasGradient = self.gradientView != nil && self.gradientContentView != nil && self.colors.count >= 3 && self.size.width > 1.0 && self.size.height > 1.0

        if settings.activeAuroraGradient, hasGradient, let contentView = self.gradientContentView {
            let auroraView: AyuGramAuroraView
            if let current = self.auroraView, current.superview === contentView {
                auroraView = current
            } else {
                self.auroraView?.removeFromSuperview()
                auroraView = AyuGramAuroraView(frame: contentView.bounds)
                auroraView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                contentView.addSubview(auroraView)
                self.auroraView = auroraView
            }
            auroraView.update(colors: self.colors)
            auroraView.isAnimationAllowed = continuousAllowed
        } else if let auroraView = self.auroraView {
            self.auroraView = nil
            auroraView.isAnimationAllowed = false
            auroraView.removeFromSuperview()
        }

        let grain = min(1.0, max(0.0, settings.activeGradientGrain))
        if grain > 0.001, hasGradient, let hostView = self.hostView, let gradientView = self.gradientView, gradientView.superview === hostView, let tile = AyuGramWallpaperEffectsController.grainTile() {
            let grainLayer: SimpleLayer
            if let current = self.grainLayer {
                grainLayer = current
            } else {
                grainLayer = SimpleLayer()
                grainLayer.compositingFilter = "overlayBlendMode"
                grainLayer.backgroundColor = UIColor(patternImage: tile).cgColor
                self.grainLayer = grainLayer
            }
            if grainLayer.superlayer !== hostView.layer {
                grainLayer.removeFromSuperlayer()
                hostView.layer.insertSublayer(grainLayer, above: gradientView.layer)
            }
            grainLayer.frame = CGRect(origin: CGPoint(), size: self.size)
            grainLayer.opacity = Float(grain) * AyuGramWallpaperEffectsController.grainMaxOpacity
        } else if let grainLayer = self.grainLayer {
            self.grainLayer = nil
            grainLayer.removeFromSuperlayer()
        }

        let parallaxWanted = settings.activeDeepParallax && hasGradient && AyuGramDeviceTilt.shared.isAvailable
        if parallaxWanted, let hostView = self.hostView {
            if self.trackingView == nil || self.trackingView?.superview !== hostView {
                if let trackingView = self.trackingView {
                    trackingView.windowChanged = nil
                    trackingView.removeFromSuperview()
                }
                let trackingView = AyuGramWindowTrackingView(frame: CGRect())
                hostView.addSubview(trackingView)
                trackingView.windowChanged = { [weak self] in
                    self?.reconcile()
                }
                self.trackingView = trackingView
            }
        } else if let trackingView = self.trackingView {
            self.trackingView = nil
            trackingView.windowChanged = nil
            trackingView.removeFromSuperview()
        }

        let parallaxRunning = parallaxWanted && continuousAllowed && self.trackingView?.window != nil
        if parallaxRunning {
            if self.tiltListener == nil {
                self.tiltListener = AyuGramDeviceTilt.shared.addListener({ [weak self] tilt in
                    self?.applyParallax(tilt: tilt)
                })
            }
        } else {
            if let tiltListener = self.tiltListener {
                self.tiltListener = nil
                AyuGramDeviceTilt.shared.removeListener(tiltListener)
            }
            self.resetParallax()
        }
    }

    private func applyParallax(tilt: CGPoint) {
        guard let gradientView = self.gradientView else {
            return
        }
        let size = self.size
        guard size.width > 1.0, size.height > 1.0 else {
            return
        }

        var vector = CGPoint(x: tilt.x, y: -tilt.y)
        if let screen = gradientView.window?.windowScene?.screen {
            let origin = screen.fixedCoordinateSpace.convert(CGPoint(), to: screen.coordinateSpace)
            let end = screen.fixedCoordinateSpace.convert(vector, to: screen.coordinateSpace)
            vector = CGPoint(x: end.x - origin.x, y: end.y - origin.y)
        }

        let fullTilt = AyuGramWallpaperEffectsController.fullTilt
        let amount = AyuGramWallpaperEffectsController.backgroundAmount
        let normalizedX = max(-1.0, min(1.0, vector.x / fullTilt))
        let normalizedY = max(-1.0, min(1.0, vector.y / fullTilt))
        let offset = CGPoint(x: -normalizedX * amount, y: -normalizedY * amount)

        let scale = 1.0 + 2.0 * amount / min(size.width, size.height)
        let backgroundTransform = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1.0), CATransform3DMakeTranslation(offset.x, offset.y, 0.0))
        gradientView.layer.sublayerTransform = backgroundTransform

        if let patternLayer = self.patternLayer {
            let relative = AyuGramWallpaperEffectsController.patternDepth - 1.0
            let maxShift = amount * relative
            let widthFraction = 1.0 / (1.0 + 2.0 * maxShift / size.width)
            let heightFraction = 1.0 / (1.0 + 2.0 * maxShift / size.height)
            let shiftX = offset.x * relative
            let shiftY = offset.y * relative
            patternLayer.contentsRect = CGRect(
                x: (1.0 - widthFraction) * 0.5 - shiftX * widthFraction / size.width,
                y: (1.0 - heightFraction) * 0.5 - shiftY * heightFraction / size.height,
                width: widthFraction,
                height: heightFraction
            )
        }

        if let auroraView = self.auroraView {
            let relative = AyuGramWallpaperEffectsController.auroraDepth - 1.0
            auroraView.layer.sublayerTransform = CATransform3DMakeTranslation(offset.x * relative, offset.y * relative, 0.0)
        }

        self.isParallaxApplied = true
    }

    private func resetParallax() {
        guard self.isParallaxApplied else {
            return
        }
        self.isParallaxApplied = false
        self.gradientView?.layer.sublayerTransform = CATransform3DIdentity
        self.patternLayer?.contentsRect = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
        self.auroraView?.layer.sublayerTransform = CATransform3DIdentity
    }

    private static func grainTile() -> UIImage? {
        if let cachedGrainTile = AyuGramWallpaperEffectsController.cachedGrainTile {
            return cachedGrainTile
        }
        let side = 128
        var pixels = [UInt8](repeating: 128, count: side * side)
        var random = AyuGramSplitMix64(seed: 0x5DEECE66D)
        for index in 0 ..< pixels.count {
            let value = random.next()
            let sum = Int(value & 0xff) + Int((value >> 8) & 0xff) + Int((value >> 16) & 0xff)
            pixels[index] = UInt8(clamping: (sum - 382) / 2 + 128)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        guard let cgImage = CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage, scale: 2.0, orientation: .up)
        AyuGramWallpaperEffectsController.cachedGrainTile = image
        return image
    }
}
