#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
"""Check String Catalogs or exchange one language as JSON; Python standard library only."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'MicRelay/Resources'
CATALOGS = ('Localizable', 'InfoPlist')
LANGUAGE = re.compile(r'[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\Z')
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hlLjzt])?([@diuoxXfFgGeEaAcsp])')


def placeholders(value):
    result = []
    sequential = 0
    for match in FORMAT.finditer(value.replace('%%', '')):
        sequential += 1
        position = int(match[1]) if match[1] else sequential
        result.append((position, (match[2] or '') + match[3]))
    return Counter(result)


def read_catalogs():
    return {name: json.loads((RESOURCES / (name + '.xcstrings')).read_text()) for name in CATALOGS}


def text(entry, language):
    return entry.get('localizations', {}).get(language, {}).get('stringUnit', {}).get('value')


def languages(catalogs):
    return sorted({language for catalog in catalogs.values() for entry in catalog['strings'].values()
                   for language in entry.get('localizations', {})})


def check(catalogs, check_project=True):
    supported = languages(catalogs)
    if not {'ja', 'en'}.issubset(supported):
        raise ValueError('The Japanese source and English translations are required.')
    count = 0
    for name, catalog in catalogs.items():
        if catalog['sourceLanguage'] != 'ja':
            raise ValueError(f'{name}: sourceLanguage must remain ja.')
        for key, entry in catalog['strings'].items():
            if entry.get('shouldTranslate') is False:
                continue
            source = text(entry, 'ja')
            if not source:
                raise ValueError(f'{name}/{key}: missing Japanese source.')
            for language in supported:
                unit = entry.get('localizations', {}).get(language, {}).get('stringUnit', {})
                value = unit.get('value')
                if not isinstance(value, str) or not value.strip() or unit.get('state') != 'translated':
                    raise ValueError(f'{name}/{key}: missing or unfinished {language} translation.')
                if placeholders(value) != placeholders(source):
                    raise ValueError(f'{name}/{key}: {language} format placeholders differ from Japanese.')
            count += 1
    # All application-owned text uses explicit, stable keys. Do not scan legal license bodies.
    keys = catalogs['Localizable']['strings']
    for path in (ROOT / 'MicRelay').rglob('*.swift'):
        source = path.read_text()
        for key in re.findall(r'String\(localized:\s*"([^"\\]+)"', source):
            if key not in keys:
                raise ValueError(f'{path.relative_to(ROOT)}: missing catalog key {key}.')
        for line in source.splitlines():
            if re.search(r'"[^"\n]*[ぁ-んァ-ヶ一-龯]', line) and 'defaultValue:' not in line and not line.lstrip().startswith('//'):
                raise ValueError(f'{path.relative_to(ROOT)}: Japanese text must use String(localized:defaultValue:).')
    if check_project:
        project = (ROOT / 'project.yml').read_text()
        match = re.search(r'^  knownRegions: \[([^\]]+)\]', project, re.M)
        if not match or set(map(str.strip, match[1].split(','))) != set(supported):
            raise ValueError('project.yml knownRegions must match catalog languages; run the import command or update it.')
    return count, supported


def export_language(catalogs, language, output):
    tables = {}
    for name, catalog in catalogs.items():
        tables[name] = {key: {'source': text(entry, 'ja'), 'translation': text(entry, language) or ''}
                        for key, entry in catalog['strings'].items() if entry.get('shouldTranslate') is not False}
    output.write_text(json.dumps({'language': language, 'tables': tables}, ensure_ascii=False, indent=2) + '\n')
    print(f'Exported {language}: {output}')


def import_language(catalogs, language, input_path):
    payload = json.loads(input_path.read_text())
    if language == 'ja':
        raise ValueError('Edit Japanese source text in Swift and the catalog together; import is for translations.')
    if payload.get('language') != language or set(payload.get('tables', {})) != set(CATALOGS):
        raise ValueError('The language or catalog tables do not match this project.')
    for name, catalog in catalogs.items():
        expected = {key for key, entry in catalog['strings'].items() if entry.get('shouldTranslate') is not False}
        rows = payload['tables'][name]
        if set(rows) != expected:
            raise ValueError(f'{name}: translation keys are incomplete or unknown; export a fresh template.')
        for key, row in rows.items():
            entry = catalog['strings'][key]
            if row.get('source') != text(entry, 'ja'):
                raise ValueError(f'{name}/{key}: Japanese source changed; export a fresh template.')
            value = row.get('translation')
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f'{name}/{key}: translation is empty.')
            if placeholders(value) != placeholders(text(entry, 'ja')):
                raise ValueError(f'{name}/{key}: format placeholders do not match.')
            entry.setdefault('localizations', {})[language] = {'stringUnit': {'state': 'translated', 'value': value}}
    # Validate all tables before writing any file.
    check(catalogs, check_project=False)
    for name, catalog in catalogs.items():
        (RESOURCES / (name + '.xcstrings')).write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    path = ROOT / 'project.yml'
    path.write_text(re.sub(r'^  knownRegions: \[[^\]]+\]', '  knownRegions: [' + ', '.join(languages(catalogs)) + ']', path.read_text(), flags=re.M))
    print(f'Imported {language}. Run xcodegen generate, then build and check the layout.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check')
    for name in ('export', 'import'):
        sub = commands.add_parser(name)
        sub.add_argument('--language', required=True)
        sub.add_argument('--output' if name == 'export' else '--input', type=Path, required=True)
    args = parser.parse_args()
    catalogs = read_catalogs()
    if args.command == 'check':
        count, supported = check(catalogs)
        print(f'OK: {count} translated entries across {", ".join(supported)}; placeholders and source keys checked.')
    else:
        if not LANGUAGE.fullmatch(args.language):
            raise ValueError('Use an Apple language identifier such as en, ko, zh-Hans, or pt-BR.')
        if args.command == 'export':
            export_language(catalogs, args.language, args.output)
        else:
            import_language(catalogs, args.language, args.input)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as error:
        print(f'Localization error: {error}', file=sys.stderr)
        sys.exit(1)
