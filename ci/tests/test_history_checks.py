import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('ayugram_history_checks', Path(__file__).resolve().parents[1] / 'ayugram_history_checks.py')
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class OwnerBadgeChecksTests(unittest.TestCase):
    fixture = '''
    func layout() {
        return ChatMessageBubbleItemNode.applyLayout(
                ayuOwner: ayuOwner,
        )
    }
    private static func applyLayout(
        ayuOwner: Bool,
    ) -> Void {
        strongSelf.ayuOwnerBadge.isHidden = true
        if let nameNode = nameNodeSizeApply.1() {
            strongSelf.ayuOwnerBadge.isHidden = !ayuOwner || nameNode.bounds.width == 0
            if !strongSelf.ayuOwnerBadge.isHidden {
                strongSelf.clippingNode.view.addSubview(strongSelf.ayuOwnerBadge)
            }
            if boostCount > 0 {}
        }
    }
'''

    def generate(self, text):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            bubble = source / 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift'
            bubble.parent.mkdir(parents=True)
            bubble.write_text(text)
            return checks.owner_badge_test_code(source)

    def test_native_check_uses_production_badge_body(self):
        code = self.generate(self.fixture)
        self.assertIn('static func applyLayout(ayuOwner: Bool,', code)
        self.assertIn('Self.applyLayout(ayuOwner: ayuOwner,', code)
        self.assertIn('strongSelf.ayuOwnerBadge.isHidden = !ayuOwner || nameNode.bounds.width == 0', code)

    def test_missing_flag_parameter_or_argument_fails_before_build(self):
        for line in ['        ayuOwner: Bool,\n', '                ayuOwner: ayuOwner,\n']:
            with self.subTest(line=line):
                with self.assertRaisesRegex(ValueError, 'pass its author flag'):
                    self.generate(self.fixture.replace(line, ''))

    def test_reused_bubble_without_author_must_clear_badge(self):
        with self.assertRaisesRegex(ValueError, 'reused bubble'):
            self.generate(self.fixture.replace('        strongSelf.ayuOwnerBadge.isHidden = true\n', ''))
