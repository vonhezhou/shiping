#!/usr/bin/env python3
"""Run the production AppKit PNG renderer against a synthetic frame, without screen access."""
from pathlib import Path
import subprocess
import shutil
import tempfile

root = Path(__file__).resolve().parent.parent
source = (root / "macos/Runner/MainFlutterWindow.swift").read_text()
marker = "private enum AnnotationRenderer {"
if source.count(marker) != 1:
    raise SystemExit("AnnotationRenderer source boundary changed; update this test runner.")
renderer = marker + source.split(marker, 1)[1]
fixture = (root / "test/macos/annotation_export_fixture.swift").read_text()
with tempfile.TemporaryDirectory(prefix="fruler-render-") as directory:
    for language in ['en', 'zh-Hans']:
        shutil.copytree(root / 'macos/Runner' / f'{language}.lproj', Path(directory) / f'{language}.lproj')
    script = Path(directory) / "main.swift"
    script.write_text("import Cocoa\n" + (root / "macos/Runner/NativeStrings.swift").read_text() + "\n" + renderer + "\n" + fixture)
    raise SystemExit(subprocess.run(["swift", str(script)]).returncode)
