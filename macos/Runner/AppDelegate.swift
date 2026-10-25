import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var reopenObserver: NSObjectProtocol?
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    NativeStrings.localizeMenu(NSApp.mainMenu)
    nativeLogs.log(800, "lifecycle", "Native application launch completed.")
    mainFlutterWindow?.orderOut(nil)
    reopenObserver = DistributedNotificationCenter.default().addObserver(
      forName: FrulerInstance.reopenNotification, object: nil, queue: .main
    ) { [weak self] _ in
      NSApp.activate(ignoringOtherApps: true)
      (self?.mainFlutterWindow as? MainFlutterWindow)?.presentHistory()
    }
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    nativeLogs.log(800, "lifecycle", "Application termination requested.")
    if (mainFlutterWindow as? MainFlutterWindow)?.requestQuitConfirmation() == true {
      return .terminateLater
    }
    return super.applicationShouldTerminate(sender)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      (mainFlutterWindow as? MainFlutterWindow)?.presentHistory()
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
  static func acquire(logFailure: (String) -> Void) -> Bool {
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
      let message = "Single instance initialization failed: errorType=\(String(reflecting: type(of: error)))."
      logFailure(message)
      let alert = NSAlert()
      alert.messageText = NativeStrings.text("instance.failure_title")
      alert.informativeText = NativeStrings.text("instance.failure_detail", error.localizedDescription)
      alert.runModal()
      return false
    }
  }
}
