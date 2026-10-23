#!/usr/bin/env python3
"""Exercise the production advisory lock in separate processes, without launching UI."""
import pathlib
import subprocess
import shutil
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "macos/Runner/AppDelegate.swift").read_text()
production = source[source.index("enum FrulerInstance {"):]
with tempfile.TemporaryDirectory(prefix="fruler-instance-") as directory:
    folder = pathlib.Path(directory)
    for language in ['en', 'zh-Hans']:
        shutil.copytree(root / 'macos/Runner' / f'{language}.lproj', folder / f'{language}.lproj')
    swift = folder / "main.swift"
    swift.write_text("import Cocoa\nimport Darwin\n" + (root / "macos/Runner/NativeStrings.swift").read_text() + "\n" + production + '''
let url = URL(fileURLWithPath: CommandLine.arguments[1])
if let fd = try FrulerInstance.lock(at: url) {
  print("acquired"); fflush(stdout)
  _ = readLine()
  close(fd)
} else { print("duplicate") }
''')
    binary = folder / "instance-probe"
    subprocess.run(["xcrun", "swiftc", str(swift), "-o", str(binary)], check=True)
    command = [str(binary), str(folder / "instance.lock")]
    first = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert first.stdout.readline().strip() == "acquired"
        second = subprocess.run(command, capture_output=True, text=True, timeout=10, check=True)
        assert second.stdout.strip() == "duplicate", second.stdout
    finally:
        first.communicate(input="\n", timeout=10)
    third = subprocess.run(command, input="\n", capture_output=True, text=True, timeout=10, check=True)
    assert third.stdout.strip() == "acquired", third.stdout
    # The inode remains, but process exit releases the lock; no stale PID cleanup needed.
    assert (folder / "instance.lock").exists()
print("单实例原生回归通过：跨进程互斥、重复启动拒绝与退出后重新获取")
