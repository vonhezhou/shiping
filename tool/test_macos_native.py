#!/usr/bin/env python3
"""Run the Xcode native unit suite in the integration sandbox."""
import os
import pathlib
import platform
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
flutter = env.get('FRULER_FLUTTER', 'flutter')
commands = [
    [flutter, '--no-version-check', 'build', 'macos', '--debug', '--config-only',
     '--no-pub', '--target=lib/main.dart'],
    # 应用只允许一个实例；并行测试 runner 会相互触发退出，无法完成 XCTest 握手。
    ['xcodebuild', '-workspace', 'macos/Runner.xcworkspace', '-scheme', 'Runner',
     '-configuration', 'Debug', '-destination', f'platform=macOS,arch={platform.machine()}',
     '-derivedDataPath', 'build/macos', '-only-testing:RunnerTests',
     '-parallel-testing-enabled', 'NO', 'test'],
]
for command in commands:
    result = subprocess.run(command, cwd=root, env=env)
    if result.returncode:
        sys.exit(result.returncode)
