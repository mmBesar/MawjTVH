#!/usr/bin/env python3
"""Cheap pre-flight checks that do not need the Dart SDK.

* duplicate string getters inside l10n files, or across strings.dart and
  tvh_strings.dart;
* every `strings.<name>` used in lib/ is defined.
"""
import glob
import re
import sys

members = {}
bad = False
for f in ('lib/l10n/strings.dart', 'lib/l10n/tvh_strings.dart'):
    s = open(f).read()
    for m in re.finditer(r"^  (?:String|bool|int|double|List<[^>]+>)\s+(?:get\s+)?(\w+)", s, re.M):
        name = m.group(1)
        if name in members:
            print(f"duplicate: {name} ({members[name]} and {f})")
            bad = True
        members[name] = f

used = {}
for f in glob.glob('lib/**/*.dart', recursive=True):
    for m in re.finditer(r"\bstrings\.(\w+)", open(f).read()):
        used.setdefault(m.group(1), f)
for name, f in sorted(used.items()):
    if name not in members and name not in ('of', 'dart'):
        print(f"undefined strings.{name} (first used in {f})")
        bad = True
sys.exit(1 if bad else 0)
