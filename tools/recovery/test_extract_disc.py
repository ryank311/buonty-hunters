"""Boundary tests for the disc recovery reader; no game data needed."""
import struct
import unittest
from extract_disc import safe_path, zdb_entries


def archive(name=b'RUN\\WEAP_MDL.ZED', offset=252, size=4):
    data = bytearray(256)
    struct.pack_into('<I', data, 0, 0xfc)
    struct.pack_into('<I', data, 0x98, 1)
    struct.pack_into('<I', data, 0xa0, 92)
    data[0xa4:0xa4+len(name)] = name
    struct.pack_into('<II', data, 0xe4, offset, size)
    data[252:256] = b'TEST'
    return bytes(data)


class ExtractionTests(unittest.TestCase):
    def test_preserves_named_payload(self):
        data = archive()
        entry, = zdb_entries(data)
        self.assertEqual(entry['name'], 'RUN/WEAP_MDL.ZED')
        self.assertEqual(data[entry['offset']:entry['offset']+entry['size']], b'TEST')

    def test_rejects_path_escape(self):
        for path in ('../escape', '/absolute', 'RUN/../../escape', 'C:\\escape'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                safe_path(path)

    def test_rejects_payload_outside_archive(self):
        with self.assertRaises(ValueError):
            list(zdb_entries(archive(offset=254, size=20)))

    def test_rejects_truncated_directory(self):
        with self.assertRaises(ValueError):
            list(zdb_entries(archive()[:170]))

    def test_rejects_unterminated_name(self):
        with self.assertRaises(ValueError):
            list(zdb_entries(archive(name=b'x'*64)))


if __name__ == '__main__':
    unittest.main()
