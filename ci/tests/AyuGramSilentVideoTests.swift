import Foundation
import AVFoundation
import CoreVideo

func expect(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let movie = root.appendingPathComponent("video.mov")
let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
writer.add(input)
expect(writer.startWriting(), "Video fixture writer starts")
writer.startSession(atSourceTime: .zero)
for frame in 0 ..< 2 {
    let until = Date().addingTimeInterval(10)
    while !input.isReadyForMoreMediaData && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    expect(input.isReadyForMoreMediaData, "Video fixture input becomes ready")
    var buffer: CVPixelBuffer?
    expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess, "Pixel buffer allocation")
    let pixels = buffer!
    CVPixelBufferLockBaseAddress(pixels, [])
    memset(CVPixelBufferGetBaseAddress(pixels), 0, CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
    CVPixelBufferUnlockBaseAddress(pixels, [])
    expect(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 1)), "Video frame appended")
}
input.markAsFinished()
var finished = false
writer.finishWriting { finished = true }
let deadline = Date().addingTimeInterval(10)
while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
expect(finished && writer.status == .completed, "Video fixture completed")

let audio = root.appendingPathComponent("audio.wav")
var wave = Data()
func text(_ value: String) { wave.append(contentsOf: value.utf8) }
func little<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) } }
let sampleBytes = UInt32(48000 * 2 * 2)
text("RIFF"); little(sampleBytes + 36); text("WAVEfmt "); little(UInt32(16)); little(UInt16(1)); little(UInt16(1))
little(UInt32(48000)); little(UInt32(96000)); little(UInt16(2)); little(UInt16(16)); text("data"); little(sampleBytes)
wave.append(Data(repeating: 0, count: Int(sampleBytes)))
try wave.write(to: audio)
let source = AVMutableComposition()
let videoAsset = AVURLAsset(url: movie)
let audioAsset = AVURLAsset(url: audio)
let video = videoAsset.tracks(withMediaType: .video).first!
let sourceVideo = source.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try sourceVideo.insertTimeRange(video.timeRange, of: video, at: .zero)
sourceVideo.preferredTransform = CGAffineTransform(rotationAngle: .pi / 2)
let sound = audioAsset.tracks(withMediaType: .audio).first!
try source.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: source.duration), of: sound, at: .zero)
expect(source.tracks(withMediaType: .audio).count == 1, "Fixture includes a real audio track")
let silent = try AyuGramSilentVideo.composition(from: source)
expect(silent.tracks(withMediaType: .audio).isEmpty, "Wallpaper never passes audio tracks to AVPlayer")
expect(silent.tracks(withMediaType: .video).count == 1, "Video survives removal of audio")
expect(CMTimeCompare(silent.duration, source.duration) == 0, "Loop duration is preserved")
expect(silent.tracks(withMediaType: .video).first!.preferredTransform == sourceVideo.preferredTransform, "Portrait orientation survives")
do { _ = try AyuGramSilentVideo.composition(from: audioAsset); preconditionFailure("Audio-only media must not become a wallpaper player") }
catch AyuGramSilentVideo.Failure.noVideo {}
print("Real video and audio fixture produces a silent wallpaper with matching duration and orientation")

// The wallpaper renderer must decode frames without AVPlayer (which activates the audio session).
let renderer = AyuGramSilentVideoRenderer(url: movie)
var rendered = false
renderer.firstFrameDisplayed = { rendered = true }
renderer.start()
let renderDeadline = Date().addingTimeInterval(15)
while !rendered && Date() < renderDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
expect(rendered, "Silent renderer decodes and enqueues video frames")
renderer.stop()
print("Silent wallpaper video: audio removal, orientation and AVPlayer-free rendering passed")
