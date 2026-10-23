#!/usr/bin/env python3
"""检查 Flutter / macOS 的翻译覆盖和动态参数契约。"""
import json
import pathlib
import re
import subprocess
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[1]


def read_json(path):
    def unique(pairs):
        data = {}
        for key, value in pairs:
            assert key not in data, f'{path}: duplicate key {key}'
            data[key] = value
        return data
    return json.loads(path.read_text(), object_pairs_hook=unique)


english = read_json(root / 'lib/l10n/app_en.arb')
chinese = read_json(root / 'lib/l10n/app_zh.arb')
keys = {key for key in english if not key.startswith('@')}
assert keys == {key for key in chinese if not key.startswith('@')}, 'ARB keys differ'
for key in keys:
    parameters = set(english.get('@' + key, {}).get('placeholders', {}))
    for locale, data in [('en', english), ('zh', chinese)]:
        message = data[key]
        assert isinstance(message, str) and message.strip(), f'{locale}: empty {key}'
        actual = set(re.findall(r'\{(\w+)\s*[,}]', message))
        assert actual == parameters, f'{locale}: placeholder mismatch for {key}'

for resource in ['Localizable.strings', 'InfoPlist.strings']:
    translations = []
    for locale in ['en', 'zh-Hans']:
        path = root / 'macos/Runner' / (locale + '.lproj') / resource
        data = json.loads(subprocess.check_output(
            ['plutil', '-convert', 'json', '-o', '-', str(path)], text=True))
        assert all(isinstance(value, str) and value.strip() for value in data.values()), path
        translations.append(data)
    assert translations[0].keys() == translations[1].keys(), f'{resource}: keys differ'
    for key, value in translations[0].items():
        parameters = re.findall(r'%(?:\d+\$)?[@diuf]', value)
        assert parameters == re.findall(r'%(?:\d+\$)?[@diuf]', translations[1][key]), key
    if resource == 'Localizable.strings':
        menu = ET.parse(root / 'macos/Runner/Base.lproj/MainMenu.xib')
        for item in menu.iter('menuItem'):
            if item.get('isSeparatorItem') == 'YES':
                continue
            identifier = item.get('identifier', '')
            assert identifier.startswith('l10n.'), f'Missing menu localization: {item.attrib}'
            assert identifier[5:] in translations[0], identifier

print(f'Localization resources match: {len(keys)} Flutter messages and native tables.')
