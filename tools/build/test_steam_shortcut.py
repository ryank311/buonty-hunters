"""Steam library preservation and repeat deployment; no real Steam process needed."""
from pathlib import Path
import struct
import tempfile
import unittest

import steam_shortcut as steam


class SteamShortcutTests(unittest.TestCase):
    def test_upsert_preserves_other_shortcuts_and_existing_id(self):
        launcher = Path('/home/deck/Games/socom/play.sh')
        other = [(2, b'appid', struct.pack('<I', 123)), (1, b'AppName', b'Other game'),
                 (0, b'tags', [(1, b'0', b'Favorites')]), (7, b'unknown', b'12345678')]
        own = [(2, b'appid', struct.pack('<I', 456)), (1, b'AppName', b'play.sh'),
               (1, b'Exe', b'"' + str(launcher).encode() + b'"'), (1, b'LaunchOptions', b'--fullscreen')]
        original = steam.encode([(0, b'shortcuts', [(0, b'0', other), (0, b'1', own)])])
        updated, appid = steam.upsert(original, launcher)
        entries = steam.get(steam.decode(updated), b'shortcuts')
        self.assertEqual(entries[0][2], other)
        self.assertEqual(appid, 456)
        self.assertEqual(steam.get(entries[1][2], b'LaunchOptions'), b'--fullscreen')
        self.assertEqual(steam.upsert(updated, launcher), (updated, appid))

    def test_new_shortcut_is_non_steam_and_uses_stable_launcher(self):
        data, appid = steam.upsert(b'', Path('/home/deck/Games/socom/play.sh'))
        self.assertTrue(appid & 0x80000000)
        self.assertEqual(len(steam.get(steam.decode(data), b'shortcuts')), 1)
        self.assertEqual(steam.upsert(data, Path('/home/deck/Games/socom/play.sh')), (data, appid))

    def test_invalid_library_fails_without_repairing_it(self):
        for data in (b'\x00shortcuts\x00', b'\x09unknown\x00\x08', b'\x08trailing'):
            with self.subTest(data=data), self.assertRaises(ValueError):
                steam.upsert(data, Path('/home/deck/Games/socom/play.sh'))

    def test_art_uses_real_appid_and_backs_up_only_its_own_slots(self):
        with tempfile.TemporaryDirectory() as temporary:
            grid = Path(temporary)
            (grid / '42p.png').write_bytes(b'old cover')
            (grid / '99p.jpg').write_bytes(b'another game')
            steam.install_artwork(grid, 42, b'box art')
            self.assertTrue(steam.artwork_current(grid, 42, b'box art'))
            self.assertEqual((grid / '99p.jpg').read_bytes(), b'another game')
            self.assertEqual(next(grid.glob('42p.png.socom-*.bak')).read_bytes(), b'old cover')
            before = sorted(grid.iterdir())
            steam.install_artwork(grid, 42, b'box art')
            self.assertEqual(sorted(grid.iterdir()), before)
