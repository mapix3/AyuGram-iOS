import re
import subprocess
from pathlib import Path


def settings_search_test_code(source: Path):
    text = (source / 'Swiftgram/SGItemListUI/Sources/SGItemListUI.swift').read_text(encoding='utf-8')

    def declaration(start):
        first = text.index(start)
        opening = text.index('{', first)
        depth = 1
        end = opening + 1
        while depth:
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        return text[first:end] + '\n'

    entry = declaration('public enum SGItemListUIEntry<')
    rendering = declaration('    public func item(presentationData:')
    if entry.count(rendering.rstrip('\n')) != 1:
        raise ValueError('Settings entry rendering method must be removed once from the native search check')
    entry = entry.replace(rendering.rstrip('\n'), '').replace(': ItemListNodeEntry {', ': Comparable {', 1)
    search = declaration('public func filterSGItemListUIEntrires<')
    return '''import Foundation
public typealias ItemListSectionId = Int32
public struct UIColor: Equatable {}
public enum ItemListActionKind: Equatable { case generic, destructive }
''' + declaration('public protocol SGItemListSection:') + entry + search + '''
enum TestSection: Int32, SGItemListSection { case search, background, unrelated }
enum TestSetting: Hashable { case dim }
typealias TestEntry = SGItemListUIEntry<TestSection, TestSetting, TestSetting, TestSetting, TestSetting, TestSetting>
let search: TestEntry = .searchInput(id: 0, section: .search, title: NSAttributedString(string: ""), text: "", placeholder: "Search")
let header: TestEntry = .header(id: 1, section: .background, text: "Background Dimming", badge: nil)
let slider: TestEntry = .rangedPercentageSlider(id: 2, section: .background, settingName: .dim, value: 60, minimum: 20, maximum: 90)
let notice: TestEntry = .notice(id: 3, section: .background, text: "Adjust the background contrast")
let unrelated: TestEntry = .toggle(id: 4, section: .unrelated, settingName: .dim, value: true, text: "Notifications", enabled: true)
let entries = [search, header, slider, notice, unrelated]
func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
expect(filterSGItemListUIEntrires(entries: entries, by: nil) == entries, "Missing query preserves all settings")
expect(filterSGItemListUIEntrires(entries: entries, by: "") == entries, "Empty query preserves all settings")
expect(filterSGItemListUIEntrires(entries: entries, by: "BACKGROUND") == [search, header, slider, notice], "Matching section includes its ranged slider")
expect(filterSGItemListUIEntrires(entries: entries, by: "contrast") == [search, header, slider, notice], "Matching description retains its preceding slider")
expect(filterSGItemListUIEntrires(entries: entries, by: "notifications") == [search, unrelated], "Unrelated section excludes slider")
expect(filterSGItemListUIEntrires(entries: entries, by: "missing") == [search], "No match preserves only search input")
expect(slider.section == TestSection.background.rawValue && slider.stableId == 2, "Ranged slider preserves section and identity")
let changedRange: TestEntry = .rangedPercentageSlider(id: 2, section: .background, settingName: .dim, value: 60, minimum: 30, maximum: 90)
expect(slider != changedRange, "A range change refreshes the slider")
print("Settings entry switches and search passed with ranged sliders")
'''


def check_settings_search(source: Path, output: Path):
    tests = output / 'SettingsSearchTests.swift'
    tests.write_text(settings_search_test_code(source), encoding='utf-8')
    binary = output / 'settings-search-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', tests, '-o', binary], check=True)
    subprocess.run([binary], check=True)


def check_custom_compatibility(source: Path):
    minimum = re.search(r'^minimum_os_version\s*=\s*"([0-9.]+)"', (source / 'Telegram/BUILD').read_text(), re.M)
    if not minimum:
        raise ValueError('Minimum iOS version is missing')
    output = source / 'build-input/ayu-compatibility'
    output.mkdir(parents=True, exist_ok=True)
    check_settings_search(source, output)
    paths = [
        'Swiftgram/SGSettingsUI/Sources/AyuGramAppearanceController.swift',
        'Swiftgram/SGSimpleSettings/Sources/AyuGramAppearance.swift',
        'submodules/Display/Source/AyuGramBackdropView.swift',
        'submodules/Display/Source/AyuGramSilentVideo.swift',
    ]
    preview = source / 'Swiftgram/SGSettingsUI/Sources/AyuGramAppearancePreviewItem.swift'
    if preview.exists():
        paths.append(preview.relative_to(source).as_posix())
    inputs = []
    controller = (source / paths[0]).read_text()
    keys = sorted(set(re.findall(r'\bstrings\.([A-Za-z0-9_]+)', controller + (preview.read_text() if preview.exists() else ''))))
    # Application presentation/list contracts are stubbed; media APIs use their real source and iOS SDK.
    declarations = 'struct PresentationStrings {\n' + ''.join(f'    var {key}: String {{ "{key}" }}\n' for key in keys) + '}\n'
    declarations += '''struct CompatibilityPresentationData { var strings = PresentationStrings() }
struct CompatibilityValue { func with<T>(_ f: (CompatibilityPresentationData) -> T) -> T { f(CompatibilityPresentationData()) } }
struct CompatibilitySharedContext { var currentPresentationData = CompatibilityValue() }
final class AccountContext { var sharedContext = CompatibilitySharedContext() }
func i18n(_ key: String, _ language: String) -> String { key }
'''
    if preview.exists():
        declarations += '''
typealias ItemListSectionId = Int32
protocol ListViewItem {}
protocol ItemListItem { var sectionId: ItemListSectionId { get } }
struct ListViewItemLayoutParams { let width: CGFloat; let leftInset: CGFloat; let rightInset: CGFloat }
struct ListViewItemNodeLayout { let contentSize: CGSize; let insets: UIEdgeInsets }
struct ListViewItemApply {}
struct ListViewItemUpdateAnimation {}
class ListViewItemNode {
    let view = UIView()
    var contentSize = CGSize.zero
    var insets = UIEdgeInsets.zero
    init(layerBacked: Bool) {}
}
enum NoError: Error {}
final class Signal<T, E: Error> {}
final class Queue {
    static func mainQueue() -> Queue { Queue() }
    func async(_ f: @escaping () -> Void) { f() }
}
struct CompatibilityCheckColors { var foregroundColor: UIColor { .white } }
struct CompatibilityListTheme {
    var itemAccentColor: UIColor { .purple }
    var itemPrimaryTextColor: UIColor { .label }
    var blocksBackgroundColor: UIColor { .systemBackground }
    var itemBlocksBackgroundColor: UIColor { .secondarySystemBackground }
    var itemCheckColors = CompatibilityCheckColors()
}
struct CompatibilityBubbleComponents { var fill: [UIColor] { [.gray, .gray] } }
struct CompatibilityBubbleColors { var withWallpaper = CompatibilityBubbleComponents() }
struct CompatibilityMessageColors {
    var bubble = CompatibilityBubbleColors()
    var primaryTextColor: UIColor { .label }
    var secondaryTextColor: UIColor { .secondaryLabel }
    var accentTextColor: UIColor { .purple }
    var accentControlColor: UIColor { .purple }
}
struct CompatibilityMessageTheme { var incoming = CompatibilityMessageColors(); var outgoing = CompatibilityMessageColors() }
struct CompatibilityChatTheme { var message = CompatibilityMessageTheme() }
struct CompatibilityChatListTheme {
    var backgroundColor: UIColor { .black }
    var itemBackgroundColor: UIColor { .black }
    var pinnedItemBackgroundColor: UIColor { .gray }
    var titleColor: UIColor { .white }
    var messageTextColor: UIColor { .gray }
    var dateTextColor: UIColor { .gray }
    var pinnedBadgeColor: UIColor { .gray }
    var checkmarkColor: UIColor { .purple }
    var itemSeparatorColor: UIColor { .gray }
}
struct CompatibilityTheme { var list = CompatibilityListTheme(); var chat = CompatibilityChatTheme(); var chatList = CompatibilityChatListTheme() }
struct ItemListPresentationData { var theme = CompatibilityTheme(); var strings = PresentationStrings() }
'''
        declarations = 'import UIKit\n' + declarations
    stubs = output / 'ApplicationContext.swift'
    stubs.write_text(declarations)
    inputs.append(stubs)
    for relative in paths:
        text = (source / relative).read_text()
        if relative == paths[0] and 'private final class AyuGramAppearanceMediaPicker' in text:
            text = 'import Foundation\nimport UIKit\nimport PhotosUI\n' + text[text.index('private final class AyuGramAppearanceMediaPicker'):]
        text = re.sub(r'^import (?:Display|AccountContext|TelegramPresentationData|SGSimpleSettings|SGStrings|SwiftSignalKit|ItemListUI)\n', '', text, flags=re.M)
        target = output / Path(relative).name
        target.write_text(text)
        inputs.append(target)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios' + minimum.group(1), '-sdk', sdk, '-typecheck', *map(str, inputs)], check=True)
    print('Custom appearance SDK compatibility checked at iOS ' + minimum.group(1), flush=True)
    check_scoped_wallpapers(source, output)
    check_silent_video(source, output)


def check_silent_video(source: Path, output: Path):
    helper = source / 'submodules/Display/Source/AyuGramSilentVideo.swift'
    tests = Path(__file__).resolve().parent / 'ayugram-tests/AyuGramSilentVideoTests.swift'
    main = output / 'main.swift'
    main.write_text(tests.read_text(), encoding='utf-8')
    binary = output / 'silent-video-tests'
    import platform
    target = ('arm64' if platform.machine() == 'arm64' else 'x86_64') + '-apple-macos11.0'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', target, helper, main, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=40)


def check_scoped_wallpapers(source: Path, output: Path):
    model = (source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramAppearance.swift').read_text()
    if 'AyuGramAppearanceScope' not in model:
        return
    tests = model + '''
func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
let suite = "AyuAppearanceTests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: root)
}
let directory = root.appendingPathComponent("media")
let store = AyuGramAppearance(defaults: defaults, directory: directory)
let legacy = Data(#"{"fileName":"legacy.jpg","isVideo":false,"chatList":true,"conversations":true,"dim":0.6,"blur":0.2,"rowOpacity":0.65,"animateVideo":true}"#.utf8)
defaults.set(legacy, forKey: "swiftgram.ayuGram.appearance.v1")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try Data([1, 2, 3]).write(to: directory.appendingPathComponent("legacy.jpg"))
expect(store.effectiveSettings(for: .conversation).fileName == "legacy.jpg", "Existing backgrounds migrate")
let firstSuite = suite + ".first"
let firstDefaults = UserDefaults(suiteName: firstSuite)!
defer { firstDefaults.removePersistentDomain(forName: firstSuite) }
let first = AyuGramAppearance(defaults: firstDefaults, directory: root.appendingPathComponent("first-media"))
let video = root.appendingPathComponent("first.mp4")
try Data([1, 2, 3]).write(to: video)
try first.importMedia(video, isVideo: true, scope: .chatList)
expect(first.mediaURL(for: .conversation) == first.mediaURL(for: .chatList) && first.effectiveSettings(for: .conversation).isVideo, "First list video also appears in conversations")
expect(first.showsConversations, "First import enables actual conversation wallpaper")
first.reset(scope: .conversation)
expect(first.mediaURL(for: .conversation) == nil && first.mediaURL(for: .chatList) != nil, "Explicit reset restores Telegram wallpaper without removing list media")
let build21 = Data(#"{"wallpaper":{"isVideo":false,"dim":0.6,"blur":0.2,"animateVideo":true},"fileName":"legacy.jpg","isVideo":false,"chatList":true,"conversations":true,"dim":0.6,"blur":0.2,"rowOpacity":0.65,"animateVideo":true}"#.utf8)
defaults.set(build21, forKey: "swiftgram.ayuGram.appearance.v1")
expect(store.mediaURL(for: .conversation)?.lastPathComponent == "legacy.jpg", "Build 21 empty override inherits the selected photo")
defaults.set(legacy, forKey: "swiftgram.ayuGram.appearance.v1")
store.updateForScope(.chatList) { $0.dim = 0.75 }
expect(store.effectiveSettings(for: .conversation).dim == 0.6, "List adjustment preserves existing conversation")
let file = root.appendingPathComponent("input.jpg")
try Data([4, 5, 6]).write(to: file)
try store.importMedia(file, isVideo: false, scope: .chatList)
let listURL = store.mediaURL(for: .chatList)!
expect(store.mediaURL(for: .conversation)?.lastPathComponent == "legacy.jpg", "List import preserves old conversation file")
expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("legacy.jpg").path), "Shared legacy image is not removed")
try store.importMedia(file, isVideo: false, scope: .conversation)
let wallpaperURL = store.mediaURL(for: .conversation)!
expect(wallpaperURL != listURL && store.mediaURL(for: .chatList) == listURL, "Conversation import is independent")
store.updateForScope(.conversation) { $0.dim = -5; $0.blur = 8 }
expect(store.effectiveSettings(for: .conversation).dim == 0.2 && store.effectiveSettings(for: .conversation).blur == 1, "Effect ranges clamp")
store.reset(scope: .chatList)
expect(store.mediaURL(for: .chatList) == nil && store.mediaURL(for: .conversation) == wallpaperURL, "List reset preserves wallpaper")
expect(!FileManager.default.fileExists(atPath: listURL.path) && FileManager.default.fileExists(atPath: wallpaperURL.path), "Reset removes only unused file")
store.reset(scope: .conversation)
expect(store.mediaURL(for: .conversation) == nil, "Conversation reset restores native wallpaper")
store.updateForScope(.chatList) { $0.fileName = "../escape.jpg" }
expect(store.mediaURL(for: .chatList) == nil, "Invalid media path cannot escape directory")
let empty = root.appendingPathComponent("empty.jpg")
try Data().write(to: empty)
do { try store.importMedia(empty, isVideo: false); preconditionFailure("Empty media must be rejected") } catch {}
let persisted = AyuGramAppearance(defaults: defaults, directory: directory)
expect(persisted.settings == store.settings, "Scoped settings survive restart")
print("Appearance migration, independent media, effect ranges, restart and file cleanup passed")
'''
    tests_path = output / 'AppearanceTests.swift'
    tests_path.write_text(tests)
    binary = output / 'appearance-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', tests_path, '-o', binary], check=True)
    subprocess.run([binary], check=True)
