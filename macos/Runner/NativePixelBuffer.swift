import Foundation
import Darwin

/// Published IDs are weak: the capture session owns the initial buffer reference.
/// FFI acquires independent ARC references, released by Dart's external-data finalizer.
final class NativePixelBuffer {
  let data: UnsafeMutableRawPointer
  let byteCount: Int
  private(set) var id: Int64 = 0

  init?(byteCount: Int) {
    guard byteCount > 0, let data = calloc(1, byteCount) else { return nil }
    self.data = data
    self.byteCount = byteCount
    id = PixelBufferRegistry.publish(self)
  }

  func unpublish() { PixelBufferRegistry.remove(id) }

  #if FRULER_INTEGRATION_TEST
  static var liveCount: Int { PixelBufferRegistry.liveCount }
  #endif

  deinit {
    PixelBufferRegistry.destroy(id)
    free(data)
  }
}

private enum PixelBufferRegistry {
  private final class Entry {
    weak var value: NativePixelBuffer?
    init(_ value: NativePixelBuffer) { self.value = value }
  }
  private static let lock = NSLock()
  private static var nextID: Int64 = 0
  private static var buffers: [Int64: Entry] = [:]
  #if FRULER_INTEGRATION_TEST
  private static var allocations = 0
  static var liveCount: Int {
    lock.lock(); defer { lock.unlock() }
    return allocations
  }
  #endif

  static func publish(_ buffer: NativePixelBuffer) -> Int64 {
    lock.lock(); defer { lock.unlock() }
    nextID += 1
    #if FRULER_INTEGRATION_TEST
    allocations += 1
    #endif
    buffers[nextID] = Entry(buffer)
    return nextID
  }

  static func remove(_ id: Int64) {
    lock.lock(); defer { lock.unlock() }
    buffers.removeValue(forKey: id)
  }

  static func destroy(_ id: Int64) {
    lock.lock(); defer { lock.unlock() }
    buffers.removeValue(forKey: id)
    #if FRULER_INTEGRATION_TEST
    allocations -= 1
    #endif
  }

  static func acquire(_ id: Int64) -> UnsafeMutableRawPointer? {
    lock.lock(); defer { lock.unlock() }
    guard let buffer = buffers[id]?.value else { return nil }
    return Unmanaged.passRetained(buffer).toOpaque()
  }
}

// Stable C ABI; these symbols are retained by the Runner linker settings.
@_cdecl("fruler_frame_acquire")
public func frulerFrameAcquire(_ id: Int64) -> UnsafeMutableRawPointer? {
  PixelBufferRegistry.acquire(id)
}

@_cdecl("fruler_frame_data")
public func frulerFrameData(_ token: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
  guard let token = token else { return nil }
  return Unmanaged<NativePixelBuffer>.fromOpaque(token).takeUnretainedValue().data
}

@_cdecl("fruler_frame_length")
public func frulerFrameLength(_ token: UnsafeMutableRawPointer?) -> Int64 {
  guard let token = token else { return 0 }
  return Int64(Unmanaged<NativePixelBuffer>.fromOpaque(token).takeUnretainedValue().byteCount)
}

@_cdecl("fruler_frame_release")
public func frulerFrameRelease(_ token: UnsafeMutableRawPointer?) {
  guard let token = token else { return }
  Unmanaged<NativePixelBuffer>.fromOpaque(token).release()
}
