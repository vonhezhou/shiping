#!/usr/bin/env python3
"""Exercise real region recording in the isolated macOS integration app."""
import os
import pathlib
import platform
import subprocess
import sys
import tempfile
import wave

root = pathlib.Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
command = [env.get('FRULER_FLUTTER', 'flutter'), '--no-version-check', 'test',
           'integration_test/recording_test.dart', '-d', 'macos', '--no-pub',
           '--reporter', 'expanded']

# 独立进程绘制真实屏幕内容，红/绿分区用于检查选区和 Retina 坐标，
# 左侧移动白条让屏幕持续产生新帧；不会向被测采集接口注入像素。
fixture_source = r'''
import Cocoa
import AVFoundation
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// 外部应用持续播放静音 PCM，让系统音频流有真实的采样时钟，且不打扰用户。
let audio = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
audio.numberOfLoops = -1
audio.volume = 0
guard audio.play() else { fatalError("Recording audio fixture failed to start") }
final class RecordingFixtureView: NSView {
  var tick = 0
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor(srgbRed: 0.9, green: 0.03, blue: 0.04, alpha: 1).setFill()
    bounds.fill()
    NSColor(srgbRed: 0.02, green: 0.85, blue: 0.03, alpha: 1).setFill()
    NSRect(x: 0, y: bounds.midY, width: bounds.width, height: bounds.height / 2).fill()
    NSColor.white.setFill()
    NSRect(x: CGFloat(tick % 100), y: 30, width: 12, height: bounds.height - 60).fill()
  }
}
let screen = NSScreen.screens[0].frame
let width = min(800.0, screen.width - 200)
let height = min(480.0, screen.height - 250)
let window = NSWindow(contentRect: NSRect(x: screen.minX + 100,
  y: screen.maxY - 150 - height, width: width, height: height),
  styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.title = "fruler-recording-fixture"
let view = RecordingFixtureView(frame: NSRect(x: 0, y: 0, width: width, height: height))
window.contentView = view
let observer = DistributedNotificationCenter.default().addObserver(
  forName: Notification.Name("dev.fruler.integration.raiseRegionFixture"),
  object: nil, queue: .main) { _ in
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { _ in
  view.tick += 4
  view.needsDisplay = true
}
window.orderFrontRegardless()
print("ready"); fflush(stdout)
app.run()
'''

with tempfile.TemporaryDirectory(prefix='fruler-recording-fixture-') as directory:
    folder = pathlib.Path(directory)
    # 同一回归入口先验收纯规则与真实视频/AAC编码，不依赖录屏权限。
    native_source = folder / 'main.swift'
    native_fixture = folder / 'recording-native-test'
    native_source.write_text((root / 'macos/Runner/ScreenRecorder.swift').read_text()
                             + '\n' + (root / 'test/macos/recording_fixture.swift').read_text())
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder / 'modules'),
                    '-swift-version', '5', '-target', f'{platform.machine()}-apple-macos14.0',
                    str(native_source), '-o', str(native_fixture)], check=True)
    native_temporary = folder / 'native-data'
    native_temporary.mkdir()
    native_env = env.copy()
    native_env['TMPDIR'] = str(native_temporary)
    subprocess.run([str(native_fixture)], env=native_env, check=True)
    source = folder / 'main.swift'
    fixture = folder / 'recording-fixture'
    audio = folder / 'silence.wav'
    with wave.open(str(audio), 'wb') as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(bytes(48000 * 2 * 2))
    source.write_text(fixture_source)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder / 'modules'),
                    str(source), '-o', str(fixture)], check=True)
    process = subprocess.Popen([str(fixture), str(audio)], stdout=subprocess.PIPE, text=True)
    try:
        if process.stdout.readline().strip() != 'ready':
            raise SystemExit('Native recording fixture failed to start')
        result = subprocess.run(command + sys.argv[1:], cwd=root, env=env)
    finally:
        process.terminate()
        process.wait(timeout=10)
sys.exit(result.returncode)
