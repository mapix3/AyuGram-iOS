import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ayugram_sideload', Path(__file__).resolve().parents[1] / 'ayugram_sideload.py')
sideload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sideload)


class SideloadTests(unittest.TestCase):
    def test_entitlements_share_one_app_group(self):
        app = sideload.sideload_entitlements('org.example.ayu', 'ABCDE12345', 'group.org.example.ayu')
        share = sideload.sideload_entitlements('org.example.ayu.Share', 'ABCDE12345', 'group.org.example.ayu')
        self.assertEqual(app['application-identifier'], 'ABCDE12345.org.example.ayu')
        self.assertEqual(share['application-identifier'], 'ABCDE12345.org.example.ayu.Share')
        self.assertEqual(app['com.apple.security.application-groups'], share['com.apple.security.application-groups'])

    def make_app(self, root, names):
        app = Path(root) / 'Payload/Ayu.app'
        for name in names:
            (app / 'PlugIns' / (name + '.appex')).mkdir(parents=True)
        (app / 'Frameworks/Core.framework/Frameworks/Inner.framework').mkdir(parents=True)
        (app / 'Frameworks/libswiftCore.dylib').write_bytes(b'')
        return app

    def test_all_extensions_are_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(tmp, ['ShareExtension', 'NotificationContentExtension', 'NotificationServiceExtensionv1',
                                      'IntentsExtension', 'WidgetExtension', 'BroadcastUploadExtension'])
            self.assertEqual(len(sideload.check_extensions(app)), 6)
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(tmp, ['ShareExtension', 'WidgetExtension'])
            with self.assertRaisesRegex(ValueError, 'NotificationContentExtension'):
                sideload.check_extensions(app)

    def test_nested_code_is_signed_before_its_container(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(tmp, [])
            order = [path.name for path in sideload.nested_code(app)]
            self.assertLess(order.index('Inner.framework'), order.index('Core.framework'))
            self.assertIn('libswiftCore.dylib', order)


if __name__ == '__main__':
    unittest.main()
