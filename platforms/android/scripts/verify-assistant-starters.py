#!/usr/bin/env python3
"""Guard the bundled Android starter copy against the iOS/Core definitions."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[3]
swift = (root / 'Shared/Sources/RimesCore/Assistant.swift').read_text()
swift = swift[swift.index('public static let starters:'):]
fields = ['id', 'nameZH', 'nameEN', 'taglineZH', 'taglineEN', 'instructionZH',
          'instructionEN', 'placeholderZH', 'placeholderEN']
expected = []
for match in re.finditer(r'\.init\(id: "(.*?)".*?placeholderEN: "(.*?)"\)', swift, re.S):
    entry = {}
    for key in fields:
        value = re.search(r'\b' + key + r': "((?:\\.|[^"\\])*)"', match[0])
        if not value:
            raise SystemExit('Review changed Core assistant starter syntax: ' + key)
        entry[key] = json.loads('"' + value[1] + '"')
    expected.append(entry)
asset = root / 'platforms/android/app/src/main/assets/assistant-starters.json'
if not expected or json.loads(asset.read_text()) != {'version': 1, 'starters': expected}:
    raise SystemExit('Android assistant starters differ from the shared iOS definitions')
print('Android and iOS assistant starter names, instructions and translations match')
