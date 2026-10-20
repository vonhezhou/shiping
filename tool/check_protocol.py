#!/usr/bin/env python3
"""Verify checked-in Pigeon outputs match the pinned generator and schema."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
flutter = shutil.which(os.environ.get('FRULER_FLUTTER', 'flutter'))
dart = str(Path(flutter).resolve().parent / 'dart') if flutter else 'dart'
with tempfile.TemporaryDirectory(prefix='fruler-pigeon-') as folder:
    dart_output = Path(folder) / 'desktop.g.dart'
    swift_output = Path(folder) / 'Desktop.g.swift'
    schema = Path(folder) / 'desktop.dart'
    schema.write_text((root / 'pigeons/desktop.dart').read_text()
                      .replace('lib/platform/desktop.g.dart', str(dart_output))
                      .replace('macos/Runner/Desktop.g.swift', str(swift_output)))
    subprocess.run([dart, 'run', 'pigeon', '--input', str(schema)],
                   cwd=root, check=True)
    for generated, tracked in [(dart_output, root / 'lib/platform/desktop.g.dart'),
                               (swift_output, root / 'macos/Runner/Desktop.g.swift')]:
        if generated.read_bytes() != tracked.read_bytes():
            raise SystemExit(f'Stale Pigeon output: {tracked}. Run dart run pigeon --input pigeons/desktop.dart')
print('Pigeon outputs match the protocol.')
