import tempfile
import unittest
from pathlib import Path
from compile_illustrations import compile_assets


class CompileIllustrationsTests(unittest.TestCase):
    def compile(self, body):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'example.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="60">' + body + '</svg>')
            return compile_assets(root, root / 'output')

    def test_rejects_unsupported_effect_instead_of_dropping_it(self):
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            self.compile('<rect width="20" height="20" filter="url(#shadow)"/>')

    def test_rejects_external_bitmap(self):
        with self.assertRaisesRegex(ValueError, 'Only embedded JPEGs'):
            self.compile('<image width="20" height="20" href="file:///private/photo.jpg"/>')

    def test_rejects_recursive_reference(self):
        with self.assertRaisesRegex(ValueError, 'Cyclic'):
            self.compile('<defs><g id="cycle"><use href="#cycle"/></g></defs><use href="#cycle"/>')

    def test_inherited_fill_survives_use_and_identical_nodes_are_shared(self):
        archive = self.compile('<defs><rect id="box" width="10" height="10"/></defs><use href="#box" fill="#f00"/><use href="#box" fill="#f00"/>')
        root = archive['nodes'][archive['scenes']['example']['root']]
        self.assertEqual(root['children'][0], root['children'][1])
        leaf = archive['nodes'][archive['nodes'][root['children'][0]]['children'][0]]
        self.assertEqual(leaf['fill'], [1, 0, 0, 1])

    def test_rejects_duplicate_ids(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.compile('<rect id="box"/><circle id="box"/>')

    def test_localized_highlight_keeps_metadata_without_english_preview_overlay(self):
        archive = self.compile('<rect data-preview-only="true" width="30" height="14"/>'
            '<text font-family="Helvetica Neue" font-size="10" font-weight="600" '
            'data-i18n="window.trip" data-highlight-query="Japan" data-highlight-i18n="search.query" '
            'data-highlight-fill="#ffe36b" data-highlight-text-fill="#252834" '
            'data-highlight-layout="-11 14 1 2">Japan trip</text>')
        self.assertEqual(len(archive['nodes']), 2)
        text = next(n for n in archive['nodes'] if 'text' in n)
        self.assertEqual(text['text'], 'Japan trip')
        self.assertEqual(text['highlightQuery'], 'Japan')
        self.assertEqual(text['highlightLocalization'], 'search.query')
        self.assertEqual(text['highlightLayout'], [-11, 14, 1, 2])


if __name__ == '__main__':
    unittest.main()
