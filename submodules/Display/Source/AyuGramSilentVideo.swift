import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

enum AyuGramSilentVideo {
    enum Failure: Error { case noVideo }

    static func composition(from asset: AVAsset) throws -> AVMutableComposition {
        guard let video = asset.tracks(withMediaType: .video).first else {
            throw Failure.noVideo
        }
        let output = AVMutableComposition()
        guard let track = output.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.noVideo
        }
        let range = video.timeRange
        guard range.duration.isNumeric, CMTimeCompare(range.duration, .zero) > 0 else { throw Failure.noVideo }
        try track.insertTimeRange(range, of: video, at: .zero)
        track.preferredTransform = video.preferredTransform
        return output
    }
}

final class AyuGramSilentVideoRenderer {
    let layer = AVSampleBufferDisplayLayer()
    var firstFrameDisplayed: (() -> Void)?
    var loopStarted: (() -> Void)?

    private let asset: AVURLAsset
    private let queue = DispatchQueue(label: "org.ayugram.silent-video", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var pending: CMSampleBuffer?
    private var loopStartTime: CFTimeInterval = 0.0
    private var loopStartTimestamp: CMTime?
    private var loopHasFrames = false
    private var notifiedFirstFrame = false

    init(url: URL) {
        self.asset = AVURLAsset(url: url)
        self.layer.videoGravity = .resizeAspectFill
    }

    deinit {
        self.timer?.cancel()
        self.reader?.cancelReading()
    }

    func start() {
        if self.layer.status == .failed {
            self.layer.flush()
        }
        self.queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            guard self.restartLoop() else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30.0, leeway: .milliseconds(4))
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        self.queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.reader?.cancelReading()
            self.reader = nil
            self.output = nil
            self.pending = nil
        }
    }

    private func restartLoop() -> Bool {
        self.reader?.cancelReading()
        self.reader = nil
        self.output = nil
        self.pending = nil
        self.loopStartTimestamp = nil
        self.loopHasFrames = false
        guard let track = self.asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: self.asset) else {
            return false
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        self.reader = reader
        self.output = output
        self.loopStartTime = CACurrentMediaTime()
        if let loopStarted = self.loopStarted {
            DispatchQueue.main.async(execute: loopStarted)
        }
        return true
    }

    private func tick() {
        guard let output = self.output else { return }
        let elapsed = CACurrentMediaTime() - self.loopStartTime
        var frame: CMSampleBuffer?
        var frameOffset: Double = 0.0
        var reachedEnd = false
        var decodedFrames = 0
        while true {
            if decodedFrames >= 3 {
                break
            }
            let sample: CMSampleBuffer
            if let pending = self.pending {
                self.pending = nil
                sample = pending
            } else if let next = output.copyNextSampleBuffer() {
                sample = next
            } else {
                reachedEnd = true
                break
            }
            if CMSampleBufferGetNumSamples(sample) == 0 {
                continue
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            guard timestamp.isValid else { continue }
            let start = self.loopStartTimestamp ?? timestamp
            self.loopStartTimestamp = start
            let offset = CMTimeGetSeconds(CMTimeSubtract(timestamp, start))
            if offset > elapsed {
                self.pending = sample
                break
            }
            frame = sample
            frameOffset = offset
            decodedFrames += 1
        }
        if frame != nil, elapsed - frameOffset > 0.2 {
            self.loopStartTime += elapsed - frameOffset
        }
        if let frame {
            self.loopHasFrames = true
            self.display(frame)
        }
        if reachedEnd {
            if !self.loopHasFrames || !self.restartLoop() {
                self.timer?.cancel()
                self.timer = nil
            }
        }
    }

    private func display(_ sample: CMSampleBuffer) {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            if let dictionary = (attachments as NSArray).firstObject as? NSMutableDictionary {
                dictionary[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true as NSNumber
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.layer.status == .failed {
                self.layer.flush()
            }
            guard self.layer.isReadyForMoreMediaData else { return }
            self.layer.enqueue(sample)
            if !self.notifiedFirstFrame {
                self.notifiedFirstFrame = true
                self.firstFrameDisplayed?()
            }
        }
    }
}
