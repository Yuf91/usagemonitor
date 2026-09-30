#!/usr/bin/env python3
"""Local-only workaround for duplicate SwiftBridging definitions in mixed CLT installs."""
import json
import pathlib
import subprocess
root = pathlib.Path(__file__).resolve().parents[1]
swift = pathlib.Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()).resolve()
headers = swift.parent.parent / 'include' / 'swift'
old, new = headers / 'module.modulemap', headers / 'bridging.modulemap'
output = root / '.build' / 'compiler-overlay.json'
empty = root / '.build' / 'empty.modulemap'
empty.write_text('// Duplicate legacy module suppressed for this build only.\n')
roots = []
if old.exists() and new.exists() and 'module SwiftBridging' in old.read_text() and 'module SwiftBridging' in new.read_text():
    roots.append({'type':'file','name':str(old),'external-contents':str(empty)})
output.write_text(json.dumps({'version':0, 'case-sensitive':'false', 'roots':roots}))
