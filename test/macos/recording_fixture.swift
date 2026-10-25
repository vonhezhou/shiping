import Cocoa
import AVFoundation
import CoreMedia

func require(_ value: @autoclosure () -> Bool, _ message: String) {
  if !value() { fatalError(message) }
}

func testRecordingRules() throws {
  let defaults = try ScreenRecordingOptions(data: [:])
  require(defaults.frameRate == 30 && defaults.codec == "h264", "safe default encoding")
  require(defaults.showCursor && !defaults.systemAudio, "explicit audio opt-in")
  let settings: [String: Any] = ["codec": "hevc", "frameRate": 60, "quality": "high",
    "resolution": "1080p", "showCursor": false, "systemAudio": true]
  let options = try ScreenRecordingOptions(data: settings)
  require(options.codec == "hevc" && options.frameRate == 60 && options.systemAudio, "parameter parsing")
  let landscape = try options.outputSize(sourceWidth: 3840, sourceHeight: 2160)
  require(landscape.width == 1920 && landscape.height == 1080, "1080p bound")
  let portrait = try options.outputSize(sourceWidth: 2160, sourceHeight: 3840)
  require(portrait.width == 606 && portrait.height == 1080, "portrait aspect ratio")
  let small = try options.outputSize(sourceWidth: 401, sourceHeight: 301)
  require(small.width == 400 && small.height == 300, "do not upscale; encode even dimensions")
  for invalid: [String: Any] in [["codec": "vp9"], ["frameRate": 25], ["frameRate": true],
    ["frameRate": 30.5], ["quality": "invalid"], ["resolution": "4k"], ["showCursor": "yes"],
    ["systemAudio": 1]] {
    do { _ = try ScreenRecordingOptions(data: invalid); fatalError("invalid settings accepted: \(invalid)") }
    catch ScreenRecordingError.invalidOptions { }
  }
  do { _ = try defaults.outputSize(sourceWidth: 1, sourceHeight: 200); fatalError("tiny region accepted") }
  catch ScreenRecordingError.invalidRegion { }
  let low = try ScreenRecordingOptions(data: ["quality": "low"])
  let high = try ScreenRecordingOptions(data: ["quality": "high"])
  require(low.bitRate(width: 1920, height: 1080) < high.bitRate(width: 1920, height: 1080), "quality bitrate order")
}

try testRecordingRules()
print("screen recording native rules passed")

func sample(width: Int, height: Int, time: Double, red: UInt8) throws -> CMSampleBuffer {
  var pixel: CVPixelBuffer?
  require(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess,
    "pixel buffer creation")
  let image = pixel!
  CVPixelBufferLockBaseAddress(image, [])
  let base = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
  let stride = CVPixelBufferGetBytesPerRow(image)
  for y in 0..<height {
    for x in 0..<width {
      let offset = y * stride + x * 4
      base[offset] = 0; base[offset + 1] = 0; base[offset + 2] = red; base[offset + 3] = 255
    }
  }
  CVPixelBufferUnlockBaseAddress(image, [])
  var format: CMVideoFormatDescription?
  require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
    imageBuffer: image, formatDescriptionOut: &format) == noErr, "video format")
  var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
    presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 60000), decodeTimeStamp: .invalid)
  var result: CMSampleBuffer?
  require(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
    formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &result) == noErr, "video sample")
  return result!
}

func waitFor<T>(_ perform: (@escaping (Result<T, Error>) -> Void) -> Void) throws -> T {
  var reply: Result<T, Error>?
  perform { value in DispatchQueue.main.async { reply = value } }
  let deadline = Date().addingTimeInterval(15)
  while reply == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
  require(reply != nil, "operation timed out")
  return try reply!.get()
}

func audioSample(time: Double) throws -> CMSampleBuffer {
  var description = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
    mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
  var format: CMAudioFormatDescription?
  require(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
    layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
    formatDescriptionOut: &format) == noErr, "audio format")
  var block: CMBlockBuffer?
  let byteCount = 4800 * 8
  require(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
    blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
    offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block) == noErr, "audio block")
  require(CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0,
    dataLength: byteCount) == noErr, "audio silence")
  var result: CMSampleBuffer?
  require(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
    dataBuffer: block!, formatDescription: format!, sampleCount: 4800,
    presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 48000), packetDescriptions: nil,
    sampleBufferOut: &result) == noErr, "audio sample")
  return result!
}

let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("fruler-recording-native-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
let unrelated = fixtureDirectory.appendingPathComponent("unrelated.mp4.sb-keep")
try Data("preserve other recordings".utf8).write(to: unrelated)

func requireNoSidecars(_ url: URL, _ message: String) throws {
  let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
    .filter { name in
      guard name.hasPrefix(url.lastPathComponent + ".sb-") else { return false }
      let file = url.deletingLastPathComponent().appendingPathComponent(name)
      let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
      return attributes?[.type] as? FileAttributeType == .typeRegular
    }
  if !names.isEmpty {
    print("\(message): AVAssetWriter left \(names.count) media sidecars")
    try? FileManager.default.removeItem(at: fixtureDirectory)
    exit(1)
  }
  require(FileManager.default.fileExists(atPath: unrelated.path), "cleanup must preserve unrelated recordings")
}

for codec in ["h264", "hevc"] {
  let url = fixtureDirectory.appendingPathComponent("fruler-recording-\(UUID().uuidString).mp4")
  defer { try? FileManager.default.removeItem(at: url) }
  let includeAudio = codec == "hevc"
  let options = try ScreenRecordingOptions(data: ["codec": codec, "systemAudio": includeAudio])
  let writer = try ScreenRecordingWriter(url: url, width: 64, height: 48, options: options)
  var failure: Error?
  writer.onFailure = { failure = $0 }
  writer.appendVideo(try sample(width: 64, height: 48, time: 20, red: 255))
  if includeAudio {
    for index in 0..<3 { writer.appendAudio(try audioSample(time: 20 + Double(index) * 0.1)) }
  }
  // 与真实静态桌面相同，只提供第一帧；停止时必须延续最后画面。
  Thread.sleep(forTimeInterval: 0.3)
  let result: ScreenRecordingResult = try waitFor { writer.finish(completion: $0) }
  try requireNoSidecars(url, "finished encoding")
  require(failure == nil, "encoder failure")
  require(result.width == 64 && result.height == 48 && result.duration >= 0.3, "recording result")
  let inspected: (Double, CGSize, String, Int) = try waitFor { completion in
    Task {
      do {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        require(tracks.count == 1, "one video track")
        let track = tracks[0]
        let size = try await track.load(.naturalSize)
        let formats = try await track.load(.formatDescriptions)
        let code = CMFormatDescriptionGetMediaSubType(formats[0])
        let bytes: [UInt8] = [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)]
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if includeAudio {
          require(audioTracks.count == 1, "one audio track")
          let formats = try await audioTracks[0].load(.formatDescriptions)
          require(CMFormatDescriptionGetMediaSubType(formats[0]) == kAudioFormatMPEG4AAC, "AAC output")
        }
        completion(.success((CMTimeGetSeconds(duration), size, String(bytes: bytes, encoding: .ascii)!, audioTracks.count)))
      } catch { completion(.failure(error)) }
    }
  }
  require(inspected.0 >= 0.3, "static video duration must include the hold")
  require(inspected.1 == CGSize(width: 64, height: 48), "encoded region dimensions")
  require(inspected.2 == (codec == "h264" ? "avc1" : "hvc1"), "requested codec")
  require(inspected.3 == (includeAudio ? 1 : 0), "system audio is opt-in")
  try requireNoSidecars(url, "finished encoding after asset inspection")
}
let discarded = fixtureDirectory.appendingPathComponent("fruler-recording-\(UUID().uuidString).mp4")
let cancelled = try ScreenRecordingWriter(url: discarded, width: 64, height: 48,
  options: ScreenRecordingOptions(data: [:]))
cancelled.appendVideo(try sample(width: 64, height: 48, time: 0, red: 255))
let protectedDirectory = URL(fileURLWithPath: discarded.path + ".sb-directory", isDirectory: true)
let protectedLink = URL(fileURLWithPath: discarded.path + ".sb-link")
try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
try FileManager.default.createSymbolicLink(at: protectedLink, withDestinationURL: unrelated)
cancelled.discard()
require(FileManager.default.fileExists(atPath: protectedDirectory.path), "cleanup must preserve directories")
require((try? FileManager.default.destinationOfSymbolicLink(atPath: protectedLink.path)) == unrelated.path,
  "cleanup must preserve symbolic links")
require(!FileManager.default.fileExists(atPath: discarded.path), "cancelled recording must be removed")
try requireNoSidecars(discarded, "cancelled encoding")
let empty = try ScreenRecordingWriter(url: discarded, width: 64, height: 48,
  options: ScreenRecordingOptions(data: [:]))
do {
  let _: ScreenRecordingResult = try waitFor { empty.finish(completion: $0) }
  fatalError("empty recording accepted")
} catch ScreenRecordingError.empty { }
require(!FileManager.default.fileExists(atPath: discarded.path), "empty recording must be removed")
try requireNoSidecars(discarded, "empty encoding")
print("screen recording H.264/HEVC/AAC encoding, static duration and cleanup passed")

// 空闲状态下的 stop/cancel 不查询系统内容，不要求录屏权限，也不产生回调或文件。
let idleRecorder = ScreenRecorder()
var idleReplies = 0
var idleFailures = 0
idleRecorder.onFailure = { _ in idleFailures += 1 }
idleRecorder.stop { result in
  idleReplies += 1
  do { _ = try result.get(); fatalError("idle recorder stopped successfully") }
  catch ScreenRecordingError.empty { }
  catch { fatalError("unexpected idle error") }
}
idleRecorder.cancel()
idleRecorder.cancel()
require(idleReplies == 1 && idleFailures == 0 && !idleRecorder.busy, "idle lifecycle is idempotent")
