import hashlib
import importlib.util
import io
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('ayugram_integrity', Path(__file__).resolve().parents[1] / 'ayugram_integrity.py')
integrity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(integrity)


def macho(code: bytes, signature: bytes = b'') -> bytes:
    header_size = 32
    segment_size = 72 + 80
    text_offset = 0x1000
    header = struct.pack('<IiiIIIII', integrity.MH_MAGIC_64, integrity.CPU_TYPE_ARM64, 0, 6, 1, segment_size, 0, 0)
    segment = struct.pack('<II16sQQQQiiII', integrity.LC_SEGMENT_64, segment_size, b'__TEXT', 0, 0x2000, 0, 0x2000, 5, 5, 1, 0)
    section = struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT', text_offset, len(code), text_offset, 2, 0, 0, 0, 0, 0, 0)
    body = header + segment + section
    assert len(body) == header_size + segment_size
    return body.ljust(text_offset, b'\0') + code + signature


def fat(slice_data: bytes) -> bytes:
    offset = 0x4000
    header = struct.pack('>II', integrity.FAT_MAGIC, 1) + struct.pack('>iiIII', integrity.CPU_TYPE_ARM64, 0, offset, len(slice_data), 14)
    return header.ljust(offset, b'\0') + slice_data


class IntegrityTests(unittest.TestCase):
    def test_hash_covers_only_the_code(self):
        code = b'\x1f\x20\x03\xd5' * 64
        expected = hashlib.sha256(code).hexdigest()
        self.assertEqual(integrity.text_section_hash(macho(code)), expected)
        self.assertEqual(integrity.text_section_hash(macho(code, b'SIGNATURE-A')), integrity.text_section_hash(macho(code, b'OTHER-SIGNATURE')), 'Re-signing keeps the fingerprint')
        self.assertNotEqual(integrity.text_section_hash(macho(code[:-4] + b'\xc0\x03\x5f\xd6')), expected, 'Patched code changes it')
        self.assertEqual(integrity.text_section_hash(fat(macho(code))), expected, 'The arm64 slice of a fat binary is used')
        self.assertIsNone(integrity.text_section_hash(b'not a binary at all, just text'))

    def test_fingerprint_lists_app_images_but_not_extensions(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'app.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps({'CFBundleExecutable': 'Telegram'}, fmt=plistlib.FMT_BINARY))
                archive.writestr('Payload/Telegram.app/Telegram', macho(b'main' * 16))
                archive.writestr('Payload/Telegram.app/Frameworks/TelegramUIFramework.framework/TelegramUIFramework', macho(b'ui' * 32))
                archive.writestr('Payload/Telegram.app/Frameworks/TelegramUIFramework.framework/Info.plist', b'')
                archive.writestr('Payload/Telegram.app/Frameworks/libswift_Concurrency.dylib', macho(b'dy' * 32))
                archive.writestr('Payload/Telegram.app/PlugIns/Share.appex/Share', macho(b'share' * 8))
            result = integrity.fingerprint(str(ipa), 207601)
        self.assertEqual(result['build'], 207601)
        self.assertEqual(sorted(result['images']), ['Frameworks/TelegramUIFramework.framework/TelegramUIFramework', 'Frameworks/libswift_Concurrency.dylib', 'Telegram'])
        self.assertEqual(result['images']['Telegram'], hashlib.sha256(b'main' * 16).hexdigest())


if __name__ == '__main__':
    unittest.main()
