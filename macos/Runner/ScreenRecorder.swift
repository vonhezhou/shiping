import Cocoa
import ScreenCaptureKit
import AVFoundation

/// 录制选项在原生边界再次校验，避免旧偏好或通道调用产生无效编码配置。
struct ScreenRecordingOptions {
  let codec: String
  let frameRate: Int
  let quality: String
  let resolution: String
  let showCursor: Bool
  let systemAudio: Bool

  init(data: [String: Any]) throws {
    func string(_ key: String, _ fallback: String, _ allowed: [String]) throws -> String {
      guard let value = data[key] else { return fallback }
      guard let result = value as? String, allowed.contains(result) else { throw ScreenRecordingError.invalidOptions }
      return result
    }
    func flag(_ key: String, _ fallback: Bool) throws -> Bool {
      guard let value = data[key] else { return fallback }
      guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw ScreenRecordingError.invalidOptions
      }
      return number.boolValue
    }
    codec = try string("codec", "h264", ["h264", "hevc"])
    quality = try string("quality", "high", ["low", "medium", "high"])
    resolution = try string("resolution", "original", ["original", "1080p", "720p"])
    if let value = data["frameRate"] {
      guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
        [24.0, 30.0, 60.0].contains(number.doubleValue) else { throw ScreenRecordingError.invalidOptions }
      frameRate = number.intValue
    } else { frameRate = 30 }
    showCursor = try flag("showCursor", true)
    systemAudio = try flag("systemAudio", false)
  }

  func outputSize(sourceWidth: Int, sourceHeight: Int) throws -> (width: Int, height: Int) {
    guard sourceWidth >= 2, sourceHeight >= 2, sourceWidth <= 32768, sourceHeight <= 32768 else {
      throw ScreenRecordingError.invalidRegion
    }
    let bound: (Double, Double)
    switch resolution {
    case "1080p": bound = (1920, 1080)
    case "720p": bound = (1280, 720)
    default: bound = (Double(sourceWidth), Double(sourceHeight))
    }
    let scale = min(1, min(bound.0 / Double(sourceWidth), bound.1 / Double(sourceHeight)))
    // H.264/HEVC 的 4:2:0 编码使用偶数宽高，不通过拉伸补齐选区。
    return (max(2, Int(Double(sourceWidth) * scale) / 2 * 2),
      max(2, Int(Double(sourceHeight) * scale) / 2 * 2))
  }

  func bitRate(width: Int, height: Int) -> Int {
    let factor = quality == "low" ? 0.055 : quality == "medium" ? 0.10 : 0.18
    return max(500_000, min(100_000_000,
      Int(Double(width) * Double(height) * Double(frameRate) * factor * (codec == "hevc" ? 0.7 : 1))))
  }
}

enum ScreenRecordingError: LocalizedError {
  case busy, invalidOptions, invalidRegion, unavailable, empty, writeFailure
  var code: String {
    switch self {
    case .busy: return "recording_busy"
    case .invalidOptions: return "recording_options"
    case .invalidRegion: return "recording_region"
    case .unavailable: return "recording_unavailable"
    case .empty: return "recording_empty"
    case .writeFailure: return "recording_write"
    }
  }
  var errorDescription: String? { code }
}

struct ScreenRecordingResult {
  let url: URL
  let width: Int
  let height: Int
  let duration: Double
}

/// 所有 AVAssetWriter 状态只在 sampleQueue 中访问；公开生命周期及回调在主线程。
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
  private enum State { case idle, starting, recording, stopping }
  private var state = State.idle
  private var stream: SCStream?
  private var recordingWriter: ScreenRecordingWriter?
  private var sampleWriter: ScreenRecordingWriter?
  private var sampleStream: SCStream?
  private var pendingStart: ((Result<Void, Error>) -> Void)?
  private var pendingStop: ((Result<ScreenRecordingResult, Error>) -> Void)?
  private let sampleQueue = DispatchQueue(label: "dev.fruler.recording.writer", qos: .userInitiated)
  private var generation = 0
  var onFailure: ((Error) -> Void)?
  var busy: Bool { state != .idle }
  var isRecording: Bool { state == .recording }

  /// region 使用目标显示器左上角为原点的逻辑 pt，与跨屏全局坐标分离。
  func start(displayID: UInt32, region: CGRect, options: ScreenRecordingOptions, outputURL: URL,
    completion: @escaping (Result<Void, Error>) -> Void) {
    precondition(Thread.isMainThread)
    guard state == .idle else { completion(.failure(ScreenRecordingError.busy)); return }
    state = .starting
    pendingStart = completion
    generation += 1
    let token = generation
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
      DispatchQueue.main.async {
        guard let self = self, self.generation == token, self.state == .starting else { return }
        do {
          guard error == nil, let content = content,
            let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw error ?? ScreenRecordingError.unavailable
          }
          let displayBounds = CGRect(origin: .zero, size: display.frame.size)
          guard region.origin.x.isFinite, region.origin.y.isFinite, region.width.isFinite, region.height.isFinite,
            region.width > 0, region.height > 0, displayBounds.contains(region) else {
            throw ScreenRecordingError.invalidRegion
          }
          // 排除整个进程，录制开始后新出现的停止条和保存面板也不会进入视频。
          let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
          let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
          let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }
          // 缩放显示器的物理像素不等于截图 backing 像素；与框选快照共用 backingScale。
          let scale = screen?.backingScaleFactor ?? CGFloat(filter.pointPixelScale)
          guard scale.isFinite, scale > 0 else { throw ScreenRecordingError.invalidRegion }
          let sourceWidth = Int((region.width * scale).rounded())
          let sourceHeight = Int((region.height * scale).rounded())
          let size = try options.outputSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
          let configuration = SCStreamConfiguration()
          configuration.sourceRect = region
          configuration.width = size.width
          configuration.height = size.height
          configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
          configuration.queueDepth = 5
          configuration.pixelFormat = kCVPixelFormatType_32BGRA
          configuration.showsCursor = options.showCursor
          configuration.capturesAudio = options.systemAudio
          configuration.excludesCurrentProcessAudio = true
          configuration.sampleRate = 48000
          configuration.channelCount = 2
          configuration.colorSpaceName = CGColorSpace.sRGB
          configuration.scalesToFit = true
          let writer = try ScreenRecordingWriter(url: outputURL, width: size.width, height: size.height, options: options, queue: self.sampleQueue)
          writer.onFailure = { [weak self] error in
            DispatchQueue.main.async { self?.fail(error, token: token) }
          }
          self.recordingWriter = writer
          let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
          self.stream = stream
          self.sampleQueue.sync { self.sampleWriter = writer; self.sampleStream = stream }
          try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.sampleQueue)
          if options.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.sampleQueue) }
          stream.startCapture { [weak self] error in
            DispatchQueue.main.async {
              guard let self = self, self.generation == token, self.state == .starting else {
                // cancel 可能早于 startCapture 完成；启动成功后再次停止，避免遗留后台流。
                if error == nil { stream.stopCapture(completionHandler: nil) }
                return
              }
              if let error = error {
                self.releaseWriter(discard: true)
                self.stream = nil
                self.state = .idle
                self.completeStart(.failure(error))
              } else {
                self.state = .recording
                self.completeStart(.success(()))
              }
            }
          }
        } catch {
          self.releaseWriter(discard: true)
          self.stream = nil
          self.state = .idle
          self.completeStart(.failure(error))
        }
      }
    }
  }

  private func completeStart(_ result: Result<Void, Error>) {
    let completion = pendingStart
    pendingStart = nil
    completion?(result)
  }

  func stop(completion: @escaping (Result<ScreenRecordingResult, Error>) -> Void) {
    precondition(Thread.isMainThread)
    guard state == .recording, let stream = stream, let writer = recordingWriter else {
      completion(.failure(state == .idle ? ScreenRecordingError.empty : ScreenRecordingError.busy)); return
    }
    state = .stopping
    pendingStop = completion
    let token = generation
    stream.stopCapture { [weak self] error in
      guard let self = self else { return }
      self.sampleQueue.async {
        if let error = error {
          writer.discard()
          DispatchQueue.main.async {
            guard self.generation == token else { return }
            self.stream = nil; self.recordingWriter = nil; self.state = .idle
            self.sampleQueue.async {
              if self.sampleWriter === writer { self.sampleWriter = nil; self.sampleStream = nil }
            }
            self.completeStop(.failure(error))
          }
          return
        }
        writer.finish { result in
          DispatchQueue.main.async {
            guard self.generation == token else { return }
            self.stream = nil; self.recordingWriter = nil; self.state = .idle
            self.sampleQueue.async {
              if self.sampleWriter === writer { self.sampleWriter = nil; self.sampleStream = nil }
            }
            self.completeStop(result)
          }
        }
      }
    }
  }

  private func completeStop(_ result: Result<ScreenRecordingResult, Error>) {
    let completion = pendingStop
    pendingStop = nil
    completion?(result)
  }

  /// 退出或原生会话中断时销毁临时录制，不留下未完成 MP4。
  func cancel() {
    precondition(Thread.isMainThread)
    generation += 1
    state = .idle
    let existing = stream
    stream = nil
    if let existing = existing { existing.stopCapture(completionHandler: nil) }
    releaseWriter(discard: true)
    completeStart(.failure(ScreenRecordingError.unavailable))
    completeStop(.failure(ScreenRecordingError.unavailable))
  }

  private func releaseWriter(discard: Bool) {
    guard let writer = recordingWriter else { return }
    recordingWriter = nil
    sampleQueue.async {
      if self.sampleWriter === writer { self.sampleWriter = nil; self.sampleStream = nil }
      if discard { writer.discard() }
    }
  }

  private func fail(_ error: Error, token: Int) {
    guard generation == token, state == .recording || state == .starting else { return }
    // 先清理，再向上层交付；上层可能立即进入 NSAlert 的嵌套 run loop。
    let completion = pendingStart
    pendingStart = nil
    cancel()
    if let completion = completion { completion(.failure(error)) }
    else { onFailure?(error) }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.stream === stream else { return }
      self.fail(error, token: self.generation)
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard sampleBuffer.isValid, sampleStream === stream, let writer = sampleWriter else { return }
    if type == .screen {
      guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
        let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
        CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
      writer.appendVideo(sampleBuffer)
    } else if type == .audio { writer.appendAudio(sampleBuffer) }
  }
}

/// 可由原生夹具直接喂入真实 CMSampleBuffer，验证编码和静态画面尾帧，无需伪造录屏权限。
final class ScreenRecordingWriter {
  let url: URL
  let width: Int
  let height: Int
  var onFailure: ((Error) -> Void)?
  private let writer: AVAssetWriter
  private let video: AVAssetWriterInput
  private let audio: AVAssetWriterInput?
  private let frameRate: Int
  private let queue: DispatchQueue
  private var firstTime: CMTime?
  private var lastTime: CMTime?
  private var lastSample: CMSampleBuffer?
  private var firstUptime: TimeInterval = 0
  private var ended = false
  private var reportedFailure = false

  init(url: URL, width: Int, height: Int, options: ScreenRecordingOptions, queue: DispatchQueue = .main) throws {
    self.url = url; self.width = width; self.height = height; frameRate = options.frameRate
    self.queue = queue
    writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let videoSettings: [String: Any] = [AVVideoCodecKey: options.codec == "hevc" ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
      AVVideoWidthKey: width, AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: options.bitRate(width: width, height: height),
        AVVideoExpectedSourceFrameRateKey: options.frameRate, AVVideoMaxKeyFrameIntervalKey: options.frameRate * 2]]
    guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else { throw ScreenRecordingError.writeFailure }
    video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    video.expectsMediaDataInRealTime = true
    guard writer.canAdd(video) else { throw ScreenRecordingError.writeFailure }
    writer.add(video)
    if options.systemAudio {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
      input.expectsMediaDataInRealTime = true
      guard writer.canAdd(input) else { throw ScreenRecordingError.writeFailure }
      writer.add(input)
      audio = input
    } else { audio = nil }
    writer.shouldOptimizeForNetworkUse = true
  }

  func appendVideo(_ buffer: CMSampleBuffer) {
    guard !ended else { return }
    let time = CMSampleBufferGetPresentationTimeStamp(buffer)
    guard time.isNumeric else { return }
    if let lastTime = lastTime, CMTimeCompare(time, lastTime) <= 0 { return }
    if firstTime == nil {
      guard writer.startWriting() else { reportFailure(); return }
      writer.startSession(atSourceTime: time)
      firstTime = time
      firstUptime = ProcessInfo.processInfo.systemUptime
    }
    guard writer.status == .writing else { reportFailure(); return }
    guard video.isReadyForMoreMediaData else { return }
    if video.append(buffer) {
      lastTime = time
      lastSample = buffer
    } else { reportFailure() }
  }

  func appendAudio(_ buffer: CMSampleBuffer) {
    guard !ended, let audio = audio, let firstTime = firstTime, writer.status == .writing,
      CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(buffer), firstTime) >= 0 else { return }
    guard audio.isReadyForMoreMediaData else { return }
    if !audio.append(buffer) { reportFailure() }
  }

  private func reportFailure() {
    guard !reportedFailure else { return }
    reportedFailure = true
    onFailure?(writer.error ?? ScreenRecordingError.writeFailure)
  }

  func finish(completion: @escaping (Result<ScreenRecordingResult, Error>) -> Void) {
    guard !ended else { completion(.failure(ScreenRecordingError.empty)); return }
    ended = true
    guard let firstTime = firstTime, let lastTime = lastTime, let lastSample = lastSample, writer.status == .writing else {
      let error = writer.error ?? ScreenRecordingError.empty
      discard()
      completion(.failure(error))
      return
    }
    let interval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    let elapsed = CMTime(seconds: max(0, ProcessInfo.processInfo.systemUptime - firstUptime), preferredTimescale: 60000)
    let endTime = CMTimeMaximum(CMTimeAdd(firstTime, elapsed), CMTimeAdd(lastTime, interval))
    // 静止桌面不会持续送新帧；等待编码器腾出空间后补尾帧，时长覆盖到实际停止时刻。
    var finishing = true
    video.requestMediaDataWhenReady(on: queue) {
      guard finishing else { return }
      guard self.writer.status == .writing else {
        finishing = false
        let error = self.writer.error ?? ScreenRecordingError.writeFailure
        self.discard()
        completion(.failure(error))
        return
      }
      guard self.video.isReadyForMoreMediaData else { return }
      finishing = false
      var timing = CMSampleTimingInfo(duration: interval, presentationTimeStamp: endTime, decodeTimeStamp: .invalid)
      var tail: CMSampleBuffer?
      guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: lastSample,
        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &tail) == noErr,
        let tail = tail, self.video.append(tail) else {
        let error = self.writer.error ?? ScreenRecordingError.writeFailure
        self.discard()
        completion(.failure(error))
        return
      }
      self.lastSample = nil
      self.writer.endSession(atSourceTime: CMTimeAdd(endTime, interval))
      self.video.markAsFinished()
      self.audio?.markAsFinished()
      self.writer.finishWriting {
        self.queue.async {
          if self.writer.status == .completed {
            self.cleanupSidecars()
            completion(.success(ScreenRecordingResult(url: self.url, width: self.width, height: self.height,
              duration: CMTimeGetSeconds(CMTimeSubtract(CMTimeAdd(endTime, interval), firstTime)))))
          } else {
            let error = self.writer.error ?? ScreenRecordingError.writeFailure
            self.discard()
            completion(.failure(error))
          }
        }
      }
    }
    queue.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard finishing, let self = self else { return }
      finishing = false
      self.discard()
      completion(.failure(ScreenRecordingError.writeFailure))
    }
  }

  func discard() {
    ended = true
    lastSample = nil
    if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
    try? FileManager.default.removeItem(at: url)
    cleanupSidecars()
  }

  private func cleanupSidecars() {
    // 网络优化编码会留下含 mdat 的 .sb 媒体文件，完成/取消后不再依赖它们。
    // 只处理本次唯一临时输出的直接同目录普通文件，保留其他录制、目录和符号链接。
    let folder = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + ".sb-"
    guard let files = try? FileManager.default.contentsOfDirectory(at: folder,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return }
    for file in files where file.lastPathComponent.hasPrefix(prefix) {
      guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
        values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }
}
