#!/usr/bin/env python3
"""Bundle the repository's full public documents without a network dependency."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
readme = '\n\n'.join((root / name).read_text() for name in
                     ('README.md', 'README.en.md', 'README.ja.md', 'README.ko.md', 'README.es.md'))
license_text = (root / 'LICENSE').read_text() + '\n\n' + (root / 'NOTICE').read_text()
out = ['// Generated from the exact source snapshot.\n#pragma once\n#include <string>\nnamespace rimes::documents {\n']
for symbol, text in [('Readme', readme), ('License', license_text)]:
    if ')XSIMEDOC"' in text or '\0' in text:
        raise ValueError('Document contains a reserved delimiter')
    out.append(f'inline const std::string& {symbol}() {{ static const std::string document = [] {{ std::string value;\n')
    # Keep each literal below MSVC's per-literal byte limit. Documents remain UTF-8.
    for start in range(0, len(text), 4000):
        out.append('value += R"XSIMEDOC(' + text[start:start+4000] + ')XSIMEDOC";\n')
    out.append('return value; }(); return document; }\n')
out.append('}\n')
path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(''.join(out))
