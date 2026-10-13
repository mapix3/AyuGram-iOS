import re
import subprocess
from pathlib import Path
from ayugram_history_checks import declaration


def slider_test_code(source: Path):
    text = (source / 'Swiftgram/SGItemListUI/Sources/SliderPercentageItem.swift').read_text()
    helpers = declaration(text, 'private func rescalePercentageValueToSlider') + declaration(text, 'private func rescaleSliderValueToPercentageValue')
    objc = (source / 'submodules/LegacyComponents/Sources/TGPhotoEditorSliderView.m').read_text()
    formula = re.search(r'CGFloat position = (totalLength / .*);', objc).group(1)
    formula = formula.replace('_minimumValue', 'minimum').replace('_maximumValue', 'maximum').replace('ABS(', 'abs(')
    callback = re.search(r'item.updated\((Int32\(.*)\)\n', text).group(1)
    if text.count('sliderView.minimumValue = 0.0') != 3 or text.count('sliderView.maximumValue = 1.0') != 3:
        raise ValueError('Both initial and reused sliders must keep the editor range at 0–1')
    if text.count('rescalePercentageValueToSlider(CGFloat(item.value) / 100.0, minimum:') != 2:
        raise ValueError('Initial and reused slider values must both normalize the stored percentage')
    return '''import Foundation
func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
''' + helpers + '''
func editorPosition(_ value: CGFloat, minimum: CGFloat = 0, maximum: CGFloat = 1) -> CGFloat {
    let totalLength: CGFloat = 1
    return ''' + formula + '''
}
struct Item { let minimum: Int32; let maximum: Int32 }
struct Slider { let value: CGFloat }
func storedValue(_ value: CGFloat, minimum: Int32, maximum: Int32) -> Int32 {
    let item = Item(minimum: minimum, maximum: maximum)
    let sliderView = Slider(value: value)
    return ''' + callback + '''
}
expect(editorPosition(0.43, minimum: 0.35, maximum: 1) > 1, "Fixture reproduces the old 43% knob overflow")
for (minimum, maximum) in [(0, 100), (20, 90), (35, 100)] {
    for percent in minimum ... maximum {
        let value = rescalePercentageValueToSlider(CGFloat(percent) / 100, minimum: CGFloat(minimum) / 100, maximum: CGFloat(maximum) / 100)
        let position = editorPosition(value)
        expect(abs(position - CGFloat(percent - minimum) / CGFloat(maximum - minimum)) < 0.000001, "Knob position must match the real percentage")
        expect(storedValue(position, minimum: Int32(minimum), maximum: Int32(maximum)) == Int32(percent), "Dragging and reloading preserve every percentage")
    }
    expect(storedValue(-1, minimum: Int32(minimum), maximum: Int32(maximum)) == Int32(minimum), "Lower endpoint clamps")
    expect(storedValue(2, minimum: Int32(minimum), maximum: Int32(maximum)) == Int32(maximum), "Upper endpoint clamps")
}
expect(abs(editorPosition(rescalePercentageValueToSlider(0.43, minimum: 0.35, maximum: 1)) - 8.0 / 65) < 0.000001, "43% row opacity stays near the left endpoint")
expect(rescalePercentageValueToSlider(0.6, minimum: 0.6, maximum: 0.6) == 0, "Degenerate range cannot divide by zero")
expect(storedValue(0.5, minimum: 60, maximum: 60) == 60, "Degenerate range preserves its single value")
print("Slider physical position, percentage persistence and editor-range regression passed")
'''


def wallpaper_test_code(source: Path):
    chat = (source / 'submodules/TelegramUI/Sources/ChatControllerNode.swift').read_text()
    listing = (source / 'submodules/ChatListUI/Sources/Node/ChatListNode.swift').read_text()
    controller = (source / 'submodules/ChatListUI/Sources/ChatListControllerNode.swift').read_text()
    alpha = declaration(chat, '    private var ayuNativeWallpaperAlpha:')
    refresh = declaration(listing, '    public func updateAyuGramAppearance()')
    if chat.count('transition.updateAlpha(node: self.backgroundNode, alpha: self.ayuNativeWallpaperAlpha)') != 2:
        raise ValueError('Normal and loading-search layouts must preserve the custom wallpaper')
    if 'transition.updateAlpha(node: self.backgroundNode, alpha: 1.0)' in chat:
        raise ValueError('Layout must not restore an opaque Telegram wallpaper over the custom background')
    if 'backdrop.frame = self.backgroundNode.frame' not in chat or 'backdrop.frame = self.bounds' not in controller:
        raise ValueError('Loading the view after initial layout must still size the wallpaper')
    if 'itemNode.listNode.updateAyuGramAppearance()' not in controller:
        raise ValueError('Changing appearance must refresh existing pinned overscroll backgrounds')
    if 'strongSelf.ayuPinnedOverscroll = pinnedOverscroll' not in listing:
        raise ValueError('Pinned changes must preserve state for appearance toggles')
    return '''import Foundation
func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
final class AyuGramAppearance {
    static let shared = AyuGramAppearance()
    var showsChatList = false
    var showsConversations = false
}
enum Color { case clear, pinned, otherTheme }
struct ListViewKeepTopItemOverscrollBackground { let color: Color; let direction: Bool }
struct ChatListTheme { var pinnedItemBackgroundColor: Color = .pinned }
struct Theme { var chatList = ChatListTheme() }
final class Fixture {
    var theme = Theme()
    var ayuPinnedOverscroll = false
    var keepTopItemOverscrollBackground: ListViewKeepTopItemOverscrollBackground?
''' + alpha + refresh + '''
    var nativeAlpha: CGFloat { ayuNativeWallpaperAlpha }
}
let node = Fixture()
node.ayuPinnedOverscroll = true
node.updateAyuGramAppearance()
expect(node.keepTopItemOverscrollBackground?.color == .pinned && node.nativeAlpha == 1, "Native appearance keeps pinned overscroll and Telegram wallpaper")
AyuGramAppearance.shared.showsChatList = true
AyuGramAppearance.shared.showsConversations = true
node.updateAyuGramAppearance()
expect(node.keepTopItemOverscrollBackground?.color == .clear && node.nativeAlpha == 0, "Custom appearance exposes media behind the pinned header and conversation")
node.theme.chatList.pinnedItemBackgroundColor = .otherTheme
node.updateAyuGramAppearance()
expect(node.keepTopItemOverscrollBackground?.color == .clear, "Theme changes cannot cover custom media")
AyuGramAppearance.shared.showsChatList = false
AyuGramAppearance.shared.showsConversations = false
node.updateAyuGramAppearance()
expect(node.keepTopItemOverscrollBackground?.color == .otherTheme && node.nativeAlpha == 1, "Reset restores the current native theme")
node.ayuPinnedOverscroll = false
node.updateAyuGramAppearance()
expect(node.keepTopItemOverscrollBackground == nil, "Unpinning removes the overscroll area")
print("Wallpaper layout visibility, pinned header, live toggles and native fallback passed")
'''


def check_ui_regressions(source: Path):
    output = source / 'build-input/ayu-ui-regressions'
    output.mkdir(parents=True, exist_ok=True)
    for name, code in [('Slider', slider_test_code(source)), ('Wallpaper', wallpaper_test_code(source))]:
        fixture = output / (name + 'Tests.swift')
        binary = output / (name.lower() + '-tests')
        fixture.write_text(code, encoding='utf-8')
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', fixture, '-o', binary], check=True)
        subprocess.run([binary], check=True)
