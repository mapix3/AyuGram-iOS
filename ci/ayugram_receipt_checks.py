import json
from pathlib import Path
import re
import subprocess
from ayugram_history_checks import declaration


def check_receipts(source: Path):
    required = ['ServerPresence', 'ServerUnavailable', 'SendReadReceipt', 'ViewWithoutReceipt',
                'ReportPhotoView', 'View', 'SendReceipt', 'ReceiptSent', 'ReceiptError', 'ReadWarning', 'ViewWarning']
    locales = sorted((source / 'Swiftgram/SGStrings/Strings').glob('*.lproj/SGLocalizable.strings'))
    assert len(locales) == 37
    for file in locales:
        strings = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', file], text=True))
        assert all(strings.get('Ayu.' + key, '').strip() for key in required), file
        assert strings['Ayu.ServerPresence'].count('%@') == 1, file
    text = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramManualReceipts.swift').read_text()
    body = text.split('func _internal_ayuReportReadAfterSending(', 1)[1].split(' -> Signal<Bool, NoError> {', 1)[1]
    guard = body.split('    return ayuReportRead(', 1)[0].replace('return .single(false)', 'return false')
    fixture = '''
struct PeerId: Equatable { let value: Int }
struct MessageId { let peerId: PeerId; let namespace: Int }
enum Namespaces { enum Message { static let Cloud = 0 } }
final class AyuGramSettings {
    static let shared = AyuGramSettings()
    struct Snapshot { var suppressRead = true }
    var snapshot = Snapshot()
}
func shouldReport(accountPeerId: PeerId, messageId: MessageId) -> Bool {
''' + guard + '''
    return true
}
let own = PeerId(value: 1)
let target = PeerId(value: 2)
precondition(shouldReport(accountPeerId: own, messageId: MessageId(peerId: target, namespace: 0)))
precondition(!shouldReport(accountPeerId: own, messageId: MessageId(peerId: own, namespace: 0)))
precondition(!shouldReport(accountPeerId: own, messageId: MessageId(peerId: target, namespace: 1)))
precondition(!shouldReport(accountPeerId: own, messageId: MessageId(peerId: target, namespace: 2)))
AyuGramSettings.shared.snapshot.suppressRead = false
precondition(!shouldReport(accountPeerId: own, messageId: MessageId(peerId: target, namespace: 0)))
print("Send receipts exclude Saved Messages, non-cloud messages and disabled privacy")
'''
    output = source / 'build-input/ayu-receipt-checks'
    output.mkdir(parents=True, exist_ok=True)
    file = output / 'ReceiptPolicy.swift'
    file.write_text(fixture)
    binary = output / 'receipt-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', file, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=10)
    from ayugram_receipt_regressions import check_receipt_regressions
    check_receipt_regressions(source, output)
    check_gallery_receipt_alerts(source, output)
    check_context_menu_receipt_alerts(source, output)
    print('Receipt strings validated in all 37 languages; production send guard passed', flush=True)


def check_gallery_receipt_alerts(source: Path, output: Path):
    display = (source / 'submodules/Display/Source/TextAlertController.swift').read_text()
    themes = (source / 'submodules/TelegramPresentationData/Sources/ComponentsThemes.swift').read_text()
    footer = (source / 'submodules/GalleryUI/Sources/ChatItemGalleryFooterContentNode.swift').read_text()
    signature = declaration(display, 'public func standardTextAlertController(').split(' {', 1)[0].replace('public ', '')
    theme = declaration(themes, 'public extension AlertControllerTheme {')
    initializer = next(line.strip().split(' {', 1)[0] for line in theme.splitlines()
                       if 'convenience init(presentationData:' in line)
    method = declaration(footer, 'private func ayuConfirmView()')
    fixture = '''
import Foundation
class ViewController {}
enum TextAlertContentActionLayout { case horizontal }
struct TextAlertAction {
    enum ActionType { case genericAction, defaultAction }
    let type: ActionType
    let title: String
    let action: () -> Void
}
final class AlertController: ViewController {
    let title: String?
    let text: String
    let actions: [TextAlertAction]
    init(title: String?, text: String, actions: [TextAlertAction]) {
        self.title = title; self.text = text; self.actions = actions
    }
}
struct Strings { let baseLanguageCode = "en"; let Common_Cancel = "Cancel"; let Common_OK = "OK" }
struct PresentationData { let strings = Strings() }
class AlertControllerTheme {
    init() {}
''' + initializer + ''' { self.init() }
}
''' + signature + ''' { return AlertController(title: title, text: text, actions: actions) }
func i18n(_ key: String, _ language: String) -> String { return key + ":" + language }
struct PresentationBox {
    func with<T>(_ body: (PresentationData) -> T) -> T { body(PresentationData()) }
}
struct SharedContext { let currentPresentationData = PresentationBox() }
final class Disposable {}
struct ReceiptSignal {
    let result: Bool
    func startStandalone(next: (Bool) -> Void) -> Disposable { next(result); return Disposable() }
}
infix operator |> : AdditionPrecedence
func |> (signal: ReceiptSignal, transform: (ReceiptSignal) -> ReceiptSignal) -> ReceiptSignal { transform(signal) }
func deliverOnMainQueue(_ signal: ReceiptSignal) -> ReceiptSignal { signal }
final class Messages {
    var result = false
    var requests = 0
    func ayuReportContentViewed(messageId: Int) -> ReceiptSignal { requests += 1; return ReceiptSignal(result: result) }
}
struct Engine { let messages = Messages() }
struct Context { let sharedContext = SharedContext(); let engine = Engine() }
struct Message { let id: Int }
struct Thread { let threadId: Int64 }
enum ChatLocation { case peer, replyThread(Thread) }
struct ChatState { var chatLocation: ChatLocation = .peer }
var chatPresentationInterfaceState = ChatState()
final class Button { var isEnabled = true }
final class Footer {
    let context = Context()
    var currentMessage: Message? = Message(id: 1)
    var ayuViewInProgress = false
    var ayuViewButton: Button? = Button()
    var alerts: [AlertController] = []
    func ayuPresent(_ controller: ViewController, _ arguments: Any?) { alerts.append(controller as! AlertController) }
    func ayuUpdateViewButton(available: Bool) { if !available { ayuViewButton = nil } }
    func confirm() { ayuConfirmView() }
''' + method + '''
}
let footer = Footer()
footer.confirm()
precondition(footer.alerts.count == 1 && footer.context.engine.messages.requests == 0, "Opening the dialog never consumes media")
let confirm = footer.alerts[0]
precondition(confirm.title == "Ayu.ReportPhotoView:en" && confirm.text == "Ayu.ViewWarning:en")
confirm.actions[0].action()
precondition(footer.context.engine.messages.requests == 0, "Cancel never sends a receipt")
footer.currentMessage = Message(id: 2)
confirm.actions[1].action()
precondition(footer.context.engine.messages.requests == 0, "A stale gallery confirmation cannot consume another message")
footer.confirm()
footer.alerts.last!.actions[1].action()
precondition(footer.context.engine.messages.requests == 1 && footer.ayuViewButton!.isEnabled && !footer.ayuViewInProgress)
precondition(footer.alerts.last!.title == "Ayu.ReceiptError:en" && footer.alerts.last!.text.isEmpty, "Failure restores the button and presents the localized error")
footer.context.engine.messages.result = true
footer.confirm()
footer.alerts.last!.actions[1].action()
precondition(footer.context.engine.messages.requests == 2 && footer.ayuViewButton == nil, "Success removes the already-consumed media action")
print("Production gallery confirmation checked against Display alert signatures: cancel, stale message, failure and success passed")
'''
    file = output / 'GalleryReceiptTests.swift'
    file.write_text(fixture)
    binary = output / 'gallery-receipt-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', file, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=10)


def check_context_menu_receipt_alerts(source: Path, output: Path):
    menus = (source / 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift').read_text()
    alerts = (source / 'submodules/PresentationDataUtils/Sources/AlertTheme.swift').read_text()
    assert 'import PresentationDataUtils' in menus
    signature = declaration(alerts, 'public func textAlertController(').split(' {', 1)[0].replace('public ', '')
    calls = []
    for match in re.finditer(re.escape('textAlertController(context: context, title: i18n('), menus):
        opening = menus.index('(', match.start())
        depth = 1
        end = opening + 1
        quoted = False
        escaped = False
        while depth:
            char = menus[end]
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            else:
                depth += (char == '(') - (char == ')')
            end += 1
        calls.append(menus[match.start():end])
    assert len(calls) == 4, len(calls)
    fixture = '''
import Foundation
class ViewController {}
enum NoError: Error {}
struct Signal<Value, Failure: Error> {}
struct PresentationTheme {}
enum TextAlertContentActionLayout { case horizontal }
struct TextAlertAction {
    enum ActionType { case genericAction, defaultAction }
    let type: ActionType
    let title: String
    let action: () -> Void
}
final class AlertController: ViewController {
    let title: String?
    let text: String
    let actions: [TextAlertAction]
    init(title: String?, text: String, actions: [TextAlertAction]) {
        self.title = title; self.text = text; self.actions = actions
    }
}
struct Strings { let baseLanguageCode = "en"; let Common_Cancel = "Cancel"; let Common_OK = "OK" }
struct PresentationData { let strings = Strings() }
func i18n(_ key: String, _ language: String) -> String { key + ":" + language }
final class Disposable {}
struct ReceiptSignal {
    let result: Bool
    func startStandalone(next: (Bool) -> Void) -> Disposable { next(result); return Disposable() }
}
infix operator |> : AdditionPrecedence
func |> (signal: ReceiptSignal, transform: (ReceiptSignal) -> ReceiptSignal) -> ReceiptSignal { transform(signal) }
func deliverOnMainQueue(_ signal: ReceiptSignal) -> ReceiptSignal { signal }
final class Messages {
    var result = false
    var readRequests = 0
    var viewRequests = 0
    func ayuReportRead(messageId: Int, threadId: Int64?) -> ReceiptSignal { readRequests += 1; return ReceiptSignal(result: result) }
    func ayuReportContentViewed(messageId: Int) -> ReceiptSignal { viewRequests += 1; return ReceiptSignal(result: result) }
}
struct Engine { let messages = Messages() }
struct AccountContext { let engine = Engine() }
struct Message { let id: Int }
struct Thread { let threadId: Int64 }
enum ChatLocation { case peer, replyThread(Thread) }
struct ChatState { var chatLocation: ChatLocation = .peer }
var chatPresentationInterfaceState = ChatState()
final class ControllerInteraction {
    var alerts: [AlertController] = []
    func presentControllerInCurrent(_ controller: ViewController, _ arguments: Any?) { alerts.append(controller as! AlertController) }
}
''' + signature + ''' { return AlertController(title: title, text: text, actions: actions) }
let data = PresentationData()
let message = Message(id: 1)
let context = AccountContext()
let controllerInteraction = ControllerInteraction()
'''
    for index, call in enumerate(calls):
        fixture += 'func makeDialog' + str(index) + '(success: Bool) -> AlertController { return ' + call + ' as! AlertController }\n'
    fixture += '''
let readDialog = makeDialog0(success: false)
precondition(readDialog.title == "Ayu.SendReadReceipt:en" && readDialog.text == "Ayu.ReadWarning:en")
readDialog.actions[0].action()
precondition(context.engine.messages.readRequests == 0, "Cancel never sends a read receipt")
readDialog.actions[1].action()
precondition(context.engine.messages.readRequests == 1 && controllerInteraction.alerts.last!.title == "Ayu.ReceiptError:en")
context.engine.messages.result = true
readDialog.actions[1].action()
precondition(context.engine.messages.readRequests == 2 && controllerInteraction.alerts.last!.title == "Ayu.ReceiptSent:en")
let viewDialog = makeDialog2(success: false)
precondition(viewDialog.title == "Ayu.ReportPhotoView:en" && viewDialog.text == "Ayu.ViewWarning:en")
viewDialog.actions[0].action()
precondition(context.engine.messages.viewRequests == 0, "Cancel never consumes media")
context.engine.messages.result = false
viewDialog.actions[1].action()
precondition(context.engine.messages.viewRequests == 1 && controllerInteraction.alerts.last!.title == "Ayu.ReceiptError:en")
context.engine.messages.result = true
viewDialog.actions[1].action()
precondition(context.engine.messages.viewRequests == 2 && controllerInteraction.alerts.last!.title == "Ayu.ReceiptSent:en")
for success in [false, true] {
    let expected = success ? "Ayu.ReceiptSent:en" : "Ayu.ReceiptError:en"
    for dialog in [makeDialog1(success: success), makeDialog3(success: success)] {
        precondition(dialog.title == expected && dialog.text.isEmpty, "Result dialogs follow the actual nonoptional text API")
    }
}
print("Production context-menu receipt dialogs checked against PresentationDataUtils: cancel, read/view failure and success passed")
'''
    file = output / 'ContextMenuReceiptTests.swift'
    file.write_text(fixture)
    binary = output / 'context-menu-receipt-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', file, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=10)
