#!/usr/bin/env python3
"""Check app and vendored UI translations against AltTab's supported languages."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def formats(value):
    return sorted(re.sub(r'^%\d+\$', '%', token) for token in
                  re.findall(r'%(?:\d+\$)?(?:l{1,2}|z)?[@diufg]', value.replace('%%', '')))


def extracted_keys():
    with tempfile.TemporaryDirectory(prefix='alttab-l10n-') as temporary:
        folder = Path(temporary)
        artwork = folder / 'IllustrationStrings.swift'
        artwork.write_bytes(subprocess.check_output([sys.executable, str(ROOT / 'scripts/l10n/svg_strings.py')]))
        sources = sorted(str(p) for p in (ROOT / 'src').rglob('*.swift')) + [str(artwork)]
        subprocess.run(['genstrings', '-o', temporary, *sources], check=True, capture_output=True)
        return set(strings(folder / 'Localizable.strings'))


def validate():
    app = ROOT / 'resources/l10n'
    languages = {p.stem for p in app.glob('*.lproj')}
    tables = [(app, 'Localizable'),
              (ROOT / 'vendor/ShortcutRecorder/Sources/ShortcutRecorder', 'ShortcutRecorder'),
              (ROOT / 'vendor/Sparkle/Sources/Sparkle', 'Sparkle')]
    errors = []
    preferences = (ROOT / 'src/preferences/MacroPreferences.swift').read_text()
    language_metadata = preferences.split('enum LanguagePreference:', 1)[1].split('var localizedString:', 1)[0]
    selectable = set(re.findall(r'\("[^"\n]+", "([a-z]{2}(?:-[A-Z]{2})?)"\)', language_metadata))
    if languages != selectable or len(selectable) != 21:
        errors.append(f'Localizable: expected the 21 selectable languages; missing {sorted(selectable - languages)}; extra {sorted(languages - selectable)}')
    updater = ROOT / 'vendor/Sparkle/Helpers/Updater.app/Contents/Info.plist'
    declared = set(strings(updater).get('CFBundleLocalizations', []))
    if declared != languages:
        errors.append(f'Updater: missing languages {sorted(languages - declared)}; extra {sorted(declared - languages)}')
    if set(strings(app / 'Localizable.strings')) != extracted_keys():
        errors.append('Localizable: extracted source is stale; run scripts/l10n/extract_l10n_strings.sh')
    for folder, table in tables:
        actual = {p.stem for p in folder.glob('*.lproj')}
        if actual != languages:
            errors.append(f'{table}: missing languages {sorted(languages - actual)}; extra {sorted(actual - languages)}')
        source = strings(folder / f'en.lproj/{table}.strings')
        if table == 'Localizable' and set(source) != set(strings(app / 'Localizable.strings')):
            errors.append('Localizable: English catalog differs from the extracted source')
        for language in sorted(actual):
            target = strings(folder / f'{language}.lproj/{table}.strings')
            if set(source) != set(target):
                errors.append(f'{table}/{language}: missing {sorted(set(source) - set(target))}; extra {sorted(set(target) - set(source))}')
            for key, value in source.items():
                translated = target.get(key, '')
                if not translated.strip():
                    errors.append(f'{table}/{language}: empty translation for {key!r}')
                elif formats(value) != formats(translated):
                    errors.append(f'{table}/{language}: format mismatch for {key!r}')
    return languages, errors


if __name__ == '__main__':
    supported, failures = validate()
    if failures:
        print('\n'.join(failures), file=sys.stderr)
        sys.exit(1)
    print(f'App, ShortcutRecorder and Sparkle: complete catalogs for {len(supported)} languages; formats match')
