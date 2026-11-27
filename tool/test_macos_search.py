#!/usr/bin/env python3
"""用真实 Spotlight 导入器验证应用中英文搜索元数据。"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
app = (pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else
       root / 'build/macos/Build/Products/Debug/拾屏.app').resolve()
if not app.is_dir():
    sys.exit(f'Application bundle not found: {app}')

# 测试导入不写入系统索引；验证产物而非仅检查源 plist。
with tempfile.TemporaryDirectory(prefix='fruler-search-') as directory:
    output = pathlib.Path(directory) / 'metadata.plist'
    subprocess.run(['mdimport', '-t', '-o', str(output), str(app)], check=True)
    metadata = json.loads(subprocess.check_output(
        ['plutil', '-convert', 'json', '-o', '-', str(output)], text=True))

assert metadata.get('kMDItemCFBundleIdentifier') in {
    'dev.fruler.app', 'dev.fruler.integration'}, metadata
keywords = metadata.get('kMDItemKeywords', {})
assert isinstance(keywords, dict), keywords
words = {word.casefold() for value in keywords.values()
         for word in re.split(r'[,\s]+', value)}
assert 'fruler' in words, f'Spotlight is missing the fruler keyword: {keywords}'
names = metadata.get('kMDItemDisplayName', {})
assert names.get('zh-Hans') == '拾屏', names
assert metadata.get('_kMDItemFileName') == '拾屏.app', metadata
print(f'Spotlight indexes fruler and preserves 拾屏: {app}')
