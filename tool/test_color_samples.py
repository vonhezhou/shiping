#!/usr/bin/env python3
"""Verify native color drag/drop and restoration in two real app processes."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
# AppKit can use either its shared color directory or the sandbox's directory.
# Restore both after the test processes have stopped, even if an assertion fails.
locations = [
    pathlib.Path.home() / 'Library/Colors/NSColorPanelSwatches.plist',
    pathlib.Path.home() / 'Library/Containers/dev.fruler.integration/Data/Library/Colors/NSColorPanelSwatches.plist',
]
with tempfile.TemporaryDirectory(prefix='fruler-color-samples-') as folder:
    backups = {}
    for index, path in enumerate(locations):
        if path.exists():
            backup = pathlib.Path(folder) / str(index)
            backup.write_bytes(path.read_bytes())
            backups[path] = backup
        else:
            backups[path] = None
    try:
        for phase in ['store', 'restore']:
            print(f'Native color sample phase: {phase}', flush=True)
            result = subprocess.run([sys.executable, 'tool/test_macos_integration.py',
                                     f'--dart-define=FRULER_SAMPLE_PHASE={phase}'], cwd=root)
            if result.returncode:
                raise SystemExit(result.returncode)
    finally:
        for path, backup in backups.items():
            if backup is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(backup.read_bytes())
print('Native color sample drag/drop and fresh-process restoration passed.', flush=True)
