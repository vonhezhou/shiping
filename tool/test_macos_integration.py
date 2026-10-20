#!/usr/bin/env python3
"""Run real macOS channel/UI tests under a separate bundle and sandbox.

Requires screen-recording permission for dev.fruler.integration for the full
capture workflow. Missing permission fails that workflow, never silently skips.
Cocoa input is injected only in the integration build, not in production.
"""
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
command = [env.get('FRULER_FLUTTER', 'flutter'), '--no-version-check', 'test',
           'integration_test/desktop_test.dart', '-d', 'macos', '--no-pub',
           '--reporter', 'expanded']
result = subprocess.run(command + sys.argv[1:], cwd=root, env=env)
sys.exit(result.returncode)
