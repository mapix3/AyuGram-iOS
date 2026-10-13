import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
import struct
import zlib

spec = importlib.util.spec_from_file_location('ayugram_branding', Path(__file__).resolve().parents[1] / 'ayugram_branding.py')
branding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(branding)


class BrandingArtifactTests(unittest.TestCase):
    def ipa(self, path, name='AyuGram', icons=True, images=True, correct_size=True, optimized=False):
        info = {'CFBundleDisplayName': name}
        if icons:
            info['CFBundleIcons'] = {'CFBundleAlternateIcons': {key: {'CFBundleIconFiles': [key]} for key in ['AyuClassic', 'AyuPurple', 'AyuRed']}}
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps(info))
            if images:
                for key in ['AyuClassic', 'AyuPurple', 'AyuRed']:
                    for scale, size in [(2, 120), (3, 180)]:
                        def chunk(kind, data):
                            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
                        width = size if correct_size else 1
                        image = b'\x89PNG\r\n\x1a\n'
                        if optimized:
                            image += chunk(b'CgBI', b'\x50\x00\x20\x06')
                        image += chunk(b'IHDR', struct.pack('>IIBBBBB', width, size, 8, 2, 0, 0, 0))
                        image += chunk(b'IDAT', zlib.compress(b'\x00' * ((width * 3 + 1) * size))) + chunk(b'IEND', b'')
                        archive.writestr('Payload/Telegram.app/' + key + '@' + str(scale) + 'x.png', image)
        return path

    def test_expected_branding(self):
        with tempfile.TemporaryDirectory() as tmp:
            branding.verify_branding_ipa(self.ipa(Path(tmp) / 'app.ipa'))

    def test_missing_alternates_fail_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'alternate icons'):
                branding.verify_branding_ipa(self.ipa(Path(tmp) / 'app.ipa', icons=False))

    def test_wrong_display_name_fails_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'display name'):
                branding.verify_branding_ipa(self.ipa(Path(tmp) / 'app.ipa', name='Swiftgram'))

    def test_declared_but_missing_icon_images_fail_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'Missing alternate icon image'):
                branding.verify_branding_ipa(self.ipa(Path(tmp) / 'app.ipa', images=False))

    def test_incorrect_icon_dimensions_fail_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'Invalid alternate icon image'):
                branding.verify_branding_ipa(self.ipa(Path(tmp) / 'app.ipa', correct_size=False))

    def test_apple_optimized_png_icon_headers(self):
        with tempfile.TemporaryDirectory() as tmp:
            branding.verify_branding_ipa(self.ipa(Path(tmp) / 'app.ipa', optimized=True))
