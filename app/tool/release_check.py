#!/usr/bin/env python3
"""Fails until the things only you can finish are finished (docs/07). From `app/`:
python tool/release_check.py
"""
import os
import sys

problems = []
policy = open('assets/legal/privacy_policy.md', encoding='utf8').read()
for marker in ('DRAFT', '[CONTACT EMAIL]', '[EFFECTIVE DATE]'):
    if marker in policy:
        problems.append(f'Privacy policy still contains {marker}')
if 'throw UnsupportedError' in open('lib/core/firebase/firebase_options_prod.dart', encoding='utf8').read():
    problems.append('Firebase production options are not generated')
if not os.path.exists('android/key.properties'):
    problems.append('android/key.properties is missing, so a release would use the debug key')
if open('pubspec.yaml', encoding='utf8').read().find('version: 0.') >= 0:
    problems.append('pubspec.yaml is still on a 0.x version')

for p in problems:
    print('NOT READY:', p)
print('Ready.' if not problems else f'{len(problems)} item(s) left.')
sys.exit(1 if problems else 0)
