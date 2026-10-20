#!/usr/bin/env python3
"""The macOS regression gate: unit/UI, native units, native I/O and live app."""
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
flutter = os.environ.get('FRULER_FLUTTER', 'flutter')
commands = [
    [sys.executable, 'tool/check_protocol.py'],
    [flutter, '--no-version-check', 'analyze', '--no-pub'],
    [flutter, '--no-version-check', 'test', '--no-pub', '--reporter', 'expanded'],
    [sys.executable, 'tool/test_annotation_export.py'],
    [sys.executable, 'tool/test_single_instance.py'],
    [sys.executable, 'tool/test_macos_native.py'],
    [sys.executable, 'tool/test_macos_integration.py'],
]
if sys.platform != 'darwin':
    sys.exit('The full gate requires macOS. Run flutter test for portable unit/UI tests.')
for command in commands:
    print('\nRunning: ' + ' '.join(command), flush=True)
    result = subprocess.run(command, cwd=root)
    if result.returncode:
        sys.exit(result.returncode)
print('\nAll regression checks passed.', flush=True)
