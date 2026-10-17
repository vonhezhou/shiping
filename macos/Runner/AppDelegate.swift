import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingProjectURLs: [URL] = []
  private var reopenObserver: NSObjectProtocol?
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    (mainFlutterWindow as? MainFlutterWindow)?.openProjectURLs(pendingProjectURLs)
    pendingProjectURLs.removeAll()
    reopenObserver = DistributedNotificationCenter.default().addObserver(
      forName: FrulerInstance.reopenNotification, object: nil, queue: .main
    ) { [weak self] _ in
      NSApp.activate(ignoringOtherApps: true)
      self?.mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    if let window = mainFlutterWindow as? MainFlutterWindow { window.openProjectURLs(urls) }
    else { pendingProjectURLs.append(contentsOf:urls) }
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    (mainFlutterWindow as? MainFlutterWindow)?.requestQuitConfirmation() == true ? .terminateLater : .terminateNow
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// The lock lives in the shared sandbox container for this bundle ID, across app copies.
/// Keep the descriptor open for the process lifetime; never unlink a locked inode.
enum FrulerInstance {
  private static var descriptor: Int32 = -1
  static var reopenNotification: Notification.Name {
    Notification.Name("\(Bundle.main.bundleIdentifier ?? "dev.fruler.app").showMainWindow")
  }
  static func lock(at url: URL) throws -> Int32? {
    let fd = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
    let failure = errno
    close(fd)
    if failure == EWOULDBLOCK { return nil }
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
  }
  static func acquire() -> Bool {
    if descriptor >= 0 { return true }
    do {
      let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("fruler", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      if let fd = try lock(at: folder.appendingPathComponent("instance.lock")) {
        descriptor = fd
        // A previous app version may not yet participate in the advisory lock.
        if let id = Bundle.main.bundleIdentifier,
           let peer = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: {
             $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.isFinishedLaunching && !$0.isTerminated
           }) {
          peer.activate(options: [.activateAllWindows])
          DistributedNotificationCenter.default().postNotificationName(reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
          return false
        }
        return true
      }
      if let id = Bundle.main.bundleIdentifier {
        NSRunningApplication.runningApplications(withBundleIdentifier: id)
          .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
          .activate(options: [.activateAllWindows])
      }
      DistributedNotificationCenter.default().postNotificationName(reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
      return false
    } catch {
      let alert = NSAlert()
      alert.messageText = "无法检查 fruler 的运行实例"
      alert.informativeText = "\(error.localizedDescription)\n请退出其他 fruler 后重试。"
      alert.runModal()
      return false
    }
  }
}
