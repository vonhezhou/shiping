#!/usr/bin/env python3
"""用两个独立 macOS 应用进程验证标注选项持久化，结束后恢复测试配置。"""
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
command = [env.get('FRULER_FLUTTER', 'flutter'), '--no-version-check', 'test',
           'integration_test/annotation_options_restart_test.dart', '-d', 'macos',
           '--no-pub', '--reporter', 'expanded']
written = subprocess.run(command + ['--dart-define=FRULER_OPTIONS_PHASE=write'],
                         cwd=root, env=env)
# 写入阶段失败也尝试恢复备份，保留首次失败退出码。
phase = 'read' if written.returncode == 0 else 'restore'
restored = subprocess.run(command + [f'--dart-define=FRULER_OPTIONS_PHASE={phase}'],
                          cwd=root, env=env)
sys.exit(written.returncode or restored.returncode)
