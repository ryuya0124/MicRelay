# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'localization.py'
spec = importlib.util.spec_from_file_location('localization', SCRIPT)
l10n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(l10n)


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'MicRelay/Resources').mkdir(parents=True)
        for name in l10n.CATALOGS:
            shutil.copy(l10n.RESOURCES / (name + '.xcstrings'), self.root / 'MicRelay/Resources')
        shutil.copy(l10n.ROOT / 'project.yml', self.root)
        self.old_root, self.old_resources = l10n.ROOT, l10n.RESOURCES
        l10n.ROOT, l10n.RESOURCES = self.root, self.root / 'MicRelay/Resources'
        self.addCleanup(self.restore_paths)
        self.catalogs = l10n.read_catalogs()
        self.file = self.root / 'translations.json'
        with contextlib.redirect_stdout(io.StringIO()):
            l10n.export_language(self.catalogs, 'en', self.file)
        self.payload = json.loads(self.file.read_text())

    def restore_paths(self):
        l10n.ROOT, l10n.RESOURCES = self.old_root, self.old_resources

    def test_existing_catalogs_are_complete(self):
        count, languages = l10n.check(self.catalogs)
        self.assertGreater(count, 100)
        self.assertTrue({'en', 'ja'}.issubset(languages))

    def test_positional_placeholders_allow_reordering_but_preserve_types(self):
        source = '%lld frames: %@, error %d'
        self.assertEqual(l10n.placeholders(source), l10n.placeholders('%2$@: %1$lld frames (error %3$d)'))
        self.assertNotEqual(l10n.placeholders(source), l10n.placeholders('%2$@: %1$u frames (error %3$d)'))

    def test_bad_placeholder_does_not_write_any_catalog(self):
        key = 'accessibility.spectrum_values'
        self.payload['tables']['Localizable'][key]['translation'] = 'Frames %d'
        self.assert_import_rejected_without_writes()

    def test_missing_or_blank_translation_is_rejected(self):
        self.payload['tables']['InfoPlist']['NSMicrophoneUsageDescription']['translation'] = ''
        self.assert_import_rejected_without_writes()

    def test_changed_source_is_rejected(self):
        self.payload['tables']['Localizable']['monitor.action.start']['source'] = 'old source'
        self.assert_import_rejected_without_writes()

    def test_import_adds_language_to_both_catalogs_and_project(self):
        self.payload['language'] = 'ko'
        self.file.write_text(json.dumps(self.payload))
        with contextlib.redirect_stdout(io.StringIO()):
            l10n.import_language(self.catalogs, 'ko', self.file)
        count, languages = l10n.check(l10n.read_catalogs())
        self.assertIn('ko', languages)
        self.assertGreater(count, 100)
        # Text is only a test fixture; no Korean translation is shipped by this test.

    def assert_import_rejected_without_writes(self):
        before = {path: path.read_bytes() for path in self.root.rglob('*') if path.is_file() and path != self.file}
        self.file.write_text(json.dumps(self.payload))
        with self.assertRaises(ValueError):
            l10n.import_language(copy.deepcopy(self.catalogs), 'en', self.file)
        for path, value in before.items():
            self.assertEqual(path.read_bytes(), value)


if __name__ == '__main__':
    unittest.main()
