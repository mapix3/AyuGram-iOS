import Foundation
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox
import DeviceModel
import Camera

public enum AyuGramRoundVideoQuality {
    public static let standardSide: Int = 480
    public static let standardFrameRate: Double = 30.0
    public static let maximumSide: Int = 1072
    public static let maximumStandardSide: Int = 640

    public static var side: Int = 480 {
        didSet {
            let clamped = max(standardSide, min(maximumSide, side))
            let aligned = clamped - clamped % 16
            if aligned != side {
                side = aligned
            }
        }
    }
    public static var requestedFrameRate: Double = 30.0 {
        didSet {
            if !requestedFrameRate.isFinite || requestedFrameRate < standardFrameRate {
                requestedFrameRate = standardFrameRate
            } else if requestedFrameRate > 120.0 {
                requestedFrameRate = 120.0
            }
        }
    }

    public static var prefersHEVC: Bool = false
    public static var bitrateOverride: Int? = nil {
        didSet {
            if let value = bitrateOverride, value <= 0 {
                bitrateOverride = nil
            }
        }
    }

    public static var isOverridden: Bool {
        return side != standardSide || requestedFrameRate > standardFrameRate
    }

    public static let supportsHEVCEncoding: Bool = {
        let specification: [CFString: Any] = [:]
        var encoderId: CFString?
        var properties: CFDictionary?
        let result = VTCopySupportedPropertyDictionaryForEncoder(width: 1920, height: 1080, codecType: kCMVideoCodecType_HEVC, encoderSpecification: specification as CFDictionary, encoderIDOut: &encoderId, supportedPropertiesOut: &properties)
        return result == noErr
    }()

    static var usesHEVC: Bool {
        return prefersHEVC && supportsHEVCEncoding
    }

    static var allowsDualCamera: Bool {
        return side <= 720 && requestedFrameRate <= standardFrameRate
    }

    static var candidateFrameRates: [Double] {
        var result: [Double] = []
        for value in [requestedFrameRate, 120.0, 60.0, standardFrameRate] where value <= requestedFrameRate && !result.contains(value) {
            result.append(value)
        }
        if !result.contains(standardFrameRate) {
            result.append(standardFrameRate)
        }
        return result
    }

    static func isStandard(side: Int, frameRate: Double) -> Bool {
        return side == standardSide && frameRate <= standardFrameRate
    }

    static func bitrate(side: Int, frameRate: Double) -> Int {
        if let bitrateOverride {
            return bitrateOverride
        }
        let area = Double(side * side) / Double(standardSide * standardSide)
        let motion = frameRate > standardFrameRate ? pow(frameRate / standardFrameRate, 0.6) : 1.0
        return Int(min(16_000_000.0, max(1_200_000.0, 1_200_000.0 * area * motion)))
    }

    static func outputPoolAllocationThreshold(side: Int, frameRate: Double) -> Int {
        return isStandard(side: side, frameRate: frameRate) ? 6 : 12
    }

    static func maximumPendingRenders(side: Int, frameRate: Double) -> Int {
        if isStandard(side: side, frameRate: frameRate) {
            return 1
        }
        return frameRate > standardFrameRate ? 3 : 2
    }
}

enum RoundVideoCaptureProfile: Int, CaseIterable {
    // Budget tiers: rear uses 16:9, front uses 4:3 to retain its field of view.
    case high
    case medium
    case vga

    init?(width: Int32, height: Int32, position: AVCaptureDevice.Position, allowsWideFront: Bool = false) {
        switch (position, width, height) {
        case (.back, 1920, 1080), (.front, 1920, 1440): self = .high
        case (.back, 1280, 720), (.front, 1280, 960): self = .medium
        case (_, 640, 480): self = .vga
        case (.front, 1920, 1080) where allowsWideFront: self = .high
        case (.front, 1280, 720) where allowsWideFront: self = .medium
        default: return nil
        }
    }
}

private struct RoundVideoCaptureFormatCandidate {
    let profile: RoundVideoCaptureProfile?
    let isNV12: Bool
    let frameRateRanges: [ClosedRange<Double>]
    let supportsMultiCam: Bool
    let supportsStandardStabilization: Bool
}

private func selectRoundVideoCaptureFormat(
    _ candidates: [RoundVideoCaptureFormatCandidate],
    requiresMultiCam: Bool,
    preferStabilization: Bool,
    preferMediumProfile: Bool,
    maximumProfile: RoundVideoCaptureProfile = .high,
    frameRate: Double
) -> Int? {
    let eligible = candidates.indices.filter { index in
        let candidate = candidates[index]
        guard let profile = candidate.profile, profile.rawValue >= maximumProfile.rawValue else {
            return false
        }
        return candidate.isNV12
            && (!requiresMultiCam || candidate.supportsMultiCam)
            && candidate.frameRateRanges.contains(where: { $0.contains(frameRate) })
    }
    return eligible.min { lhsIndex, rhsIndex in
        let lhs = candidates[lhsIndex]
        let rhs = candidates[rhsIndex]
        if preferStabilization, lhs.supportsStandardStabilization != rhs.supportsStandardStabilization {
            return lhs.supportsStandardStabilization
        }
        if lhs.profile != rhs.profile {
            if preferMediumProfile {
                if lhs.profile == .medium {
                    return true
                }
                if rhs.profile == .medium {
                    return false
                }
            }
            return lhs.profile!.rawValue < rhs.profile!.rawValue
        }
        let lhsMaximumFps = lhs.frameRateRanges.map(\.upperBound).max() ?? 0.0
        let rhsMaximumFps = rhs.frameRateRanges.map(\.upperBound).max() ?? 0.0
        if lhsMaximumFps != rhsMaximumFps {
            return lhsMaximumFps < rhsMaximumFps
        }
        return lhsIndex < rhsIndex
    }
}

func roundVideoCaptureCostsAreSupported(hardwareCost: Float, systemPressureCost: Float) -> Bool {
    return hardwareCost.isFinite && systemPressureCost.isFinite
        && hardwareCost <= 1.0 && systemPressureCost <= 1.0
}

func roundVideoCaptureFormat(
    for device: AVCaptureDevice,
    requiresMultiCam: Bool,
    mode: NeoCameraImpl.RoundVideoMode,
    maximumProfile: RoundVideoCaptureProfile = .high,
    frameRate: Double,
    outputSide: Int
) -> AVCaptureDevice.Format? {
    let formats = device.formats
    let candidates = formats.map { format -> RoundVideoCaptureFormatCandidate in
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let supportsMultiCam: Bool
        if #available(iOS 13.0, *) {
            supportsMultiCam = format.isMultiCamSupported
        } else {
            supportsMultiCam = false
        }
        var profile = RoundVideoCaptureProfile(width: dimensions.width, height: dimensions.height, position: device.position, allowsWideFront: frameRate > AyuGramRoundVideoQuality.standardFrameRate)
        if outputSide > AyuGramRoundVideoQuality.maximumStandardSide && Int(min(dimensions.width, dimensions.height)) < outputSide {
            profile = nil
        }
        return RoundVideoCaptureFormatCandidate(
            profile: profile,
            isNV12: subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            frameRateRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate ... $0.maxFrameRate },
            supportsMultiCam: supportsMultiCam,
            supportsStandardStabilization: format.isVideoStabilizationModeSupported(.standard)
        )
    }
    guard let index = selectRoundVideoCaptureFormat(
        candidates,
        requiresMultiCam: requiresMultiCam,
        preferStabilization: mode != .vga && device.position == .back && frameRate <= AyuGramRoundVideoQuality.standardFrameRate,
        preferMediumProfile: device.position == .front && outputSide <= 720,
        maximumProfile: mode == .vga ? .vga : maximumProfile,
        frameRate: frameRate
    ) else {
        return nil
    }
    return formats[index]
}

func roundVideoNegotiatedFrameRate(
    devices: [AVCaptureDevice],
    requiresMultiCam: Bool,
    mode: NeoCameraImpl.RoundVideoMode,
    outputSide: Int,
    candidates: [Double]
) -> Double? {
    guard !devices.isEmpty else {
        return nil
    }
    for frameRate in candidates {
        let supported = devices.allSatisfy { device in
            return roundVideoCaptureFormat(for: device, requiresMultiCam: requiresMultiCam, mode: mode, frameRate: frameRate, outputSide: outputSide) != nil
        }
        if supported {
            return frameRate
        }
    }
    return nil
}

private func supportsDualCameraCapture(forRoundVideo: Bool, mode: NeoCameraImpl.RoundVideoMode) -> Bool {
    guard #available(iOS 13.0, *), AVCaptureMultiCamSession.isMultiCamSupported, !DeviceModel.current.isIpad else {
        return false
    }
    if forRoundVideo && DeviceModel.current == .iPhoneXR {
        return false
    }
    if forRoundVideo && AyuGramRoundVideoQuality.isOverridden {
        if !AyuGramRoundVideoQuality.allowsDualCamera || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return false
        }
    }
    let outputSide = AyuGramRoundVideoQuality.side
    let positions: [AVCaptureDevice.Position] = [.back, .front]
    return positions.allSatisfy { position in
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return false
        }
        return roundVideoCaptureFormat(for: device, requiresMultiCam: true, mode: mode, frameRate: AyuGramRoundVideoQuality.standardFrameRate, outputSide: outputSide) != nil
    }
}

public final class NeoCameraImpl: CameraImpl {
    public enum RoundVideoMode: String {
        case vga
        case hdBilinear
        case hdLanczos
    }

    public static let shared = NeoCameraImpl()

    private let roundVideoMode: RoundVideoMode
    private let log: ((String) -> Void)?

    public init(roundVideoMode: RoundVideoMode = .hdBilinear, log: ((String) -> Void)? = nil) {
        self.roundVideoMode = roundVideoMode
        self.log = log
        RoundVideoDecorationProvider.shared.warmUp()
    }

    public var isIpad: Bool {
        return DeviceModel.current.isIpad
    }

    public func isDualCameraSupported(forRoundVideo: Bool) -> Bool {
        return supportsDualCameraCapture(forRoundVideo: forRoundVideo, mode: self.roundVideoMode)
    }

    public func makeCamera(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?
    ) -> CameraProtocol {
        let cameraPreviewView: CameraPreviewView?
        if let previewView {
            guard let previewView = previewView as? CameraPreviewView else {
                preconditionFailure()
            }
            cameraPreviewView = previewView
        } else {
            cameraPreviewView = nil
        }

        let cameraSecondaryPreviewView: CameraPreviewView?
        if let secondaryPreviewView {
            guard let secondaryPreviewView = secondaryPreviewView as? CameraPreviewView else {
                preconditionFailure()
            }
            cameraSecondaryPreviewView = secondaryPreviewView
        } else {
            cameraSecondaryPreviewView = nil
        }

        return CameraNeo(
            configuration: configuration,
            previewView: cameraPreviewView,
            secondaryPreviewView: cameraSecondaryPreviewView,
            useMultiCam: configuration.isDualEnabled && self.isDualCameraSupported(forRoundVideo: configuration.isRoundVideo),
            roundVideoMode: self.roundVideoMode,
            log: self.log
        )
    }

    public func makeCameraSimplePreviewView(frame: CGRect, main: Bool, roundVideo: Bool) -> CameraSimplePreviewView {
        return CameraPreviewView(frame: frame, main: main, roundVideo: roundVideo)
    }
}
