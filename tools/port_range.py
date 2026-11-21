#!/usr/bin/env python3
"""Porta a Windows los cambios de Android entre dos commits (fusión de 3 vías).

Uso: python3 tools/port_range.py ANDROID_DIR BASE TARGET VERSION
  BASE   = commit de Android desde el que ya está portado Windows.
  TARGET = commit de Android al que se quiere llegar.
Por cada archivo cambiado en lib/, assets/, shaders/, docs/ y pubspec.yaml:
  nuevo -> se copia; borrado -> se borra; modificado -> git merge-file (Windows + cambios de Android).
Luego reaplica las adaptaciones de escritorio a lo nuevo (háptica, textos).
Lista los archivos con conflictos para resolverlos a mano.
"""
import os, re, subprocess, sys, tempfile

android, base, target, version = sys.argv[1:5]
W = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCOPE = ['lib', 'assets', 'shaders', 'docs', 'pubspec.yaml']

def git(*a, text=True):
    r = subprocess.run(['git', '-C', android, *a], capture_output=True, text=text)
    if r.returncode: raise RuntimeError(r.stderr)
    return r.stdout

def show(commit, path):
    r = subprocess.run(['git', '-C', android, 'show', f'{commit}:{path}'], capture_output=True)
    return r.stdout if r.returncode == 0 else None

def is_text(b):
    return b is not None and b'\0' not in b[:4096]

changes = [l.split('\t') for l in git('diff', '--name-status', base, target, '--', *SCOPE).splitlines()]
conflicts, touched = [], []
for ch in changes:
    st, path = ch[0][0], ch[-1]
    dst = os.path.join(W, path)
    if st == 'D':
        if os.path.exists(dst): os.remove(dst)
        continue
    new = show(target, path)
    if st == 'A' or not os.path.exists(dst) or not is_text(new):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, 'wb').write(new)
        if path.endswith('.dart'): touched.append(dst)
        continue
    old = show(base, path) or b''
    with tempfile.TemporaryDirectory() as t:
        a, b = os.path.join(t, 'base'), os.path.join(t, 'theirs')
        open(a, 'wb').write(old); open(b, 'wb').write(new)
        r = subprocess.run(['git', 'merge-file', '-L', 'windows', '-L', 'android-base', '-L', 'android-nuevo', dst, a, b])
        if r.returncode > 0: conflicts.append((path, r.returncode))
    if path.endswith('.dart'): touched.append(dst)

# adaptaciones de escritorio sobre lo nuevo/tocado
for f in touched:
    s = open(f, encoding='utf-8').read(); o = s
    if 'HapticFeedback.' in s:
        s = s.replace('HapticFeedback.', 'Haptic.')
        if 'platform/haptic.dart' not in s:
            rel = os.path.relpath(os.path.join(W, 'lib', 'platform', 'haptic.dart'), os.path.dirname(f)).replace(os.sep, '/')
            s = re.sub(r"(import 'package:flutter/material.dart';\n)", r"\1import '%s';\n" % rel, s, count=1)
    s = s.replace('Teléfono', 'Este equipo').replace('teléfono', 'equipo')
    if s != o: open(f, 'w', encoding='utf-8').write(s)

open(os.path.join(W, 'VERSION'), 'w').write(version + '\n')
print('archivos cambiados en Android:', len(changes))
print('CONFLICTOS:', len(conflicts))
for p, n in conflicts: print('  ', p, n)
