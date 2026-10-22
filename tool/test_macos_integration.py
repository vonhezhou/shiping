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
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['XCODE_XCCONFIG_FILE'] = str(root / 'tool/integration.xcconfig')
command = [env.get('FRULER_FLUTTER', 'flutter'), '--no-version-check', 'test',
           'integration_test/desktop_test.dart', '-d', 'macos', '--no-pub',
           '--reporter', 'expanded']
# A separate real AppKit process supplies a visible window to detect. No mock
# window rectangles or synthetic screen images enter the production capture path.
with tempfile.TemporaryDirectory(prefix='fruler-region-fixture-') as directory:
    fixture = pathlib.Path(directory) / 'region-fixture'
    subprocess.run(['xcrun', 'swiftc', '-D', 'FRULER_INTEGRATION_TEST', str(root / 'test/macos/region_fixture.swift'),
                    '-o', str(fixture)], check=True)
    process = subprocess.Popen([str(fixture)], stdout=subprocess.PIPE, text=True)
    try:
        if process.stdout.readline().strip() != 'ready':
            raise SystemExit('Native region fixture failed to start')
        result = subprocess.run(command + sys.argv[1:], cwd=root, env=env)
    finally:
        process.terminate()
        process.wait(timeout=10)
sys.exit(result.returncode)
