import Foundation
import UIKit
import CoreText
import UniformTypeIdentifiers
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import SGSimpleSettings
import SGStrings

private class AyuGramHostController: ViewController {
    let context: AccountContext
    var presentationData: PresentationData
    let content: UIView

    init(context: AccountContext, title: String, content: UIView) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.content = content
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = title
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNodeDidLoad()
        self.displayNode.view.addSubview(self.content)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.content.frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
    }
}

private struct AyuGramFontOption {
    let id: String
    let title: String
}

private final class AyuGramFontView: UIView, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let theme: PresentationTheme
    private let locale: String
    private let tableView = UITableView(frame: CGRect(), style: .insetGrouped)
    private var sections: [(String, [AyuGramFontOption])] = []
    var present: ((UIViewController) -> Void)?

    init(theme: PresentationTheme, locale: String) {
        self.theme = theme
        self.locale = locale
        super.init(frame: CGRect())

        self.tableView.backgroundColor = .clear
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorColor = theme.list.itemBlocksSeparatorColor
        self.addSubview(self.tableView)
        self.rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.tableView.frame = self.bounds
    }

    private func rebuild() {
        var custom: [AyuGramFontOption] = []
        let settings = AyuGramPersonalization.shared.settings
        if !settings.customFontFamily.isEmpty, let url = AyuGramPersonalization.shared.customFontURL {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            custom.append(AyuGramFontOption(id: "custom", title: settings.customFontFamily))
        }
        custom.append(AyuGramFontOption(id: "import", title: i18n("Ayu.FontImport", self.locale)))
        self.sections = [
            (i18n("Ayu.FontSystem", self.locale), [
                AyuGramFontOption(id: "", title: i18n("Ayu.FontDefault", self.locale)),
                AyuGramFontOption(id: "rounded", title: i18n("Ayu.FontRounded", self.locale)),
                AyuGramFontOption(id: "serif", title: i18n("Ayu.FontSerif", self.locale)),
                AyuGramFontOption(id: "mono", title: i18n("Ayu.FontMono", self.locale))
            ]),
            (i18n("Ayu.FontBuiltIn", self.locale), ["Avenir Next", "Futura", "Gill Sans", "Optima", "Georgia", "Baskerville", "Didot", "American Typewriter", "Menlo", "Chalkboard SE", "Noteworthy", "Marker Felt"].map { AyuGramFontOption(id: $0, title: $0) }),
            (i18n("Ayu.FontCustom", self.locale), custom)
        ]
        self.tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sections[section].0
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return section == self.sections.count - 1 ? i18n("Ayu.FontRestart", self.locale) : nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].1.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let option = self.sections[indexPath.section].1[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "font") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "font")
        cell.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        cell.textLabel?.text = option.title
        cell.textLabel?.textColor = option.id == "import" ? self.theme.list.itemAccentColor : self.theme.list.itemPrimaryTextColor
        cell.detailTextLabel?.textColor = self.theme.list.itemSecondaryTextColor
        cell.tintColor = self.theme.list.itemAccentColor
        if option.id == "import" {
            cell.textLabel?.font = UIFont.systemFont(ofSize: 17.0)
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .none
        } else {
            let family = option.id == "custom" ? AyuGramPersonalization.shared.settings.customFontFamily : option.id
            cell.textLabel?.font = family.isEmpty ? UIFont.systemFont(ofSize: 17.0, weight: .semibold) : AyuGramFontOverride.make(family: family, size: 17.0, weight: .semibold)
            cell.detailTextLabel?.font = family.isEmpty ? UIFont.systemFont(ofSize: 14.0) : AyuGramFontOverride.make(family: family, size: 14.0, weight: .regular)
            cell.detailTextLabel?.text = i18n("Ayu.FontSample", self.locale)
            cell.accessoryType = AyuGramPersonalization.shared.settings.fontFamily == option.id ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = self.sections[indexPath.section].1[indexPath.row]
        if option.id == "import" {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.font], asCopy: true)
            picker.delegate = self
            self.present?(picker)
            return
        }
        let previous = AyuGramPersonalization.shared.settings.fontFamily
        AyuGramPersonalization.shared.update { $0.fontFamily = option.id }
        UISelectionFeedbackGenerator().selectionChanged()
        tableView.reloadData()
        if previous != option.id {
            self.showRestart()
        }
    }

    private func showRestart() {
        let alert = UIAlertController(title: nil, message: i18n("Ayu.FontRestart", self.locale), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present?(alert)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first, let directory = AyuGramPersonalization.fontsDirectory else {
            return
        }
        let accessing = source.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                source.stopAccessingSecurityScopedResource()
            }
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(source as CFURL) as? [CTFontDescriptor], let first = descriptors.first, let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String, !family.isEmpty else {
            let alert = UIAlertController(title: nil, message: i18n("Ayu.FontImportFailed", self.locale), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present?(alert)
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "custom-" + String(UUID().uuidString.prefix(8)) + "." + (source.pathExtension.isEmpty ? "ttf" : source.pathExtension.lowercased())
        let target = directory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            return
        }
        let old = AyuGramPersonalization.shared.customFontURL
        AyuGramPersonalization.shared.update { settings in
            settings.customFontFile = name
            settings.customFontFamily = family
            settings.fontFamily = "custom"
        }
        if let old, old != target {
            try? FileManager.default.removeItem(at: old)
        }
        CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
        self.rebuild()
        self.showRestart()
    }
}

public func ayuGramFontController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let view = AyuGramFontView(theme: presentationData.theme, locale: locale)
    let controller = AyuGramHostController(context: context, title: i18n("Ayu.Font", locale), content: view)
    view.present = { [weak controller] next in
        controller?.present(next, animated: true)
    }
    return controller
}

private let ayuGramBadgeSymbols = ["sparkles", "star.fill", "heart.fill", "flame.fill", "bolt.fill", "crown.fill", "moon.stars.fill", "sun.max.fill", "leaf.fill", "pawprint.fill", "gamecontroller.fill", "music.note", "airplane", "eye.fill", "theatermasks.fill", "wand.and.stars", "diamond.fill", "shield.fill", "checkmark.seal.fill", "hare.fill", "tortoise.fill", "ant.fill", "ladybug.fill", "fish.fill", "snowflake", "drop.fill", "cloud.fill", "atom", "infinity", "hand.peace.fill"]

private let ayuGramBadgePalettes: [(String, String)] = [("8E61F2", "C9B3FF"), ("FF4D6D", "FF9EAE"), ("FF7A00", "FFC266"), ("FFD60A", "FFF3A3"), ("2ECC71", "A8F0C6"), ("00B4D8", "90E0EF"), ("3A86FF", "9DBEFF"), ("FF006E", "8338EC"), ("111111", "555555"), ("F1F1F1", "BDBDBD"), ("00F5D4", "9B5DE5"), ("E63946", "1D3557")]

private final class AyuGramBadgeView: UIView, UITextFieldDelegate {
    private let theme: PresentationTheme
    private let locale: String
    private let scroll = UIScrollView()
    private let previewBack = UIView()
    private let preview = UIImageView()
    private let sampleName = UILabel()
    private let sampleBadge = UIImageView()
    private let enabledLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let shapeControl = UISegmentedControl()
    private let iconsTitle = UILabel()
    private var iconButtons: [UIButton] = []
    private let emojiField = UITextField()
    private let colorsTitle = UILabel()
    private var colorButtons: [UIButton] = []
    private let darkLabel = UILabel()
    private let darkSwitch = UISwitch()
    private let hint = UILabel()

    init(theme: PresentationTheme, locale: String, name: String) {
        self.theme = theme
        self.locale = locale
        super.init(frame: CGRect())

        self.scroll.alwaysBounceVertical = true
        self.addSubview(self.scroll)

        self.previewBack.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.previewBack.layer.cornerRadius = 22.0
        self.previewBack.layer.cornerCurve = .continuous
        self.scroll.addSubview(self.previewBack)
        self.preview.contentMode = .scaleAspectFit
        self.previewBack.addSubview(self.preview)
        self.sampleName.text = name
        self.sampleName.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.sampleName.textColor = theme.list.itemPrimaryTextColor
        self.previewBack.addSubview(self.sampleName)
        self.previewBack.addSubview(self.sampleBadge)

        self.enabledLabel.text = i18n("Ayu.BadgeShow", locale)
        self.enabledLabel.textColor = theme.list.itemPrimaryTextColor
        self.enabledSwitch.onTintColor = theme.list.itemAccentColor
        self.enabledSwitch.addTarget(self, action: #selector(self.enabledChanged), for: .valueChanged)
        self.scroll.addSubview(self.enabledLabel)
        self.scroll.addSubview(self.enabledSwitch)

        for (index, key) in ["Ayu.BadgeSquircle", "Ayu.BadgeCircle", "Ayu.BadgeSeal", "Ayu.BadgeNoBackground"].enumerated() {
            self.shapeControl.insertSegment(withTitle: i18n(key, locale), at: index, animated: false)
        }
        self.shapeControl.addTarget(self, action: #selector(self.shapeChanged), for: .valueChanged)
        self.scroll.addSubview(self.shapeControl)

        for label in [self.iconsTitle, self.colorsTitle] {
            label.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
            label.textColor = theme.list.sectionHeaderTextColor
            self.scroll.addSubview(label)
        }
        self.iconsTitle.text = i18n("Ayu.BadgeIcon", locale).uppercased()
        self.colorsTitle.text = i18n("Ayu.BadgeColor", locale).uppercased()

        for (index, symbol) in ayuGramBadgeSymbols.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)), for: .normal)
            button.tintColor = theme.list.itemPrimaryTextColor
            button.backgroundColor = theme.list.itemBlocksBackgroundColor
            button.layer.cornerRadius = 12.0
            button.layer.cornerCurve = .continuous
            button.addTarget(self, action: #selector(self.iconPressed(_:)), for: .touchUpInside)
            self.iconButtons.append(button)
            self.scroll.addSubview(button)
        }
        self.emojiField.placeholder = i18n("Ayu.BadgeEmoji", locale)
        self.emojiField.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.emojiField.textColor = theme.list.itemPrimaryTextColor
        self.emojiField.layer.cornerRadius = 12.0
        self.emojiField.layer.cornerCurve = .continuous
        self.emojiField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.emojiField.leftViewMode = .always
        self.emojiField.returnKeyType = .done
        self.emojiField.delegate = self
        self.emojiField.keyboardAppearance = theme.overallDarkAppearance ? .dark : .light
        self.emojiField.addTarget(self, action: #selector(self.emojiChanged), for: .editingChanged)
        self.scroll.addSubview(self.emojiField)

        for (index, palette) in ayuGramBadgePalettes.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            var badge = AyuGramCustomBadge()
            badge.shape = 1
            badge.symbol = ""
            badge.top = palette.0
            badge.bottom = palette.1
            button.setImage(ayuGramCustomBadgeImage(badge, size: 36.0), for: .normal)
            button.layer.cornerRadius = 20.0
            button.layer.borderWidth = 2.0
            button.addTarget(self, action: #selector(self.colorPressed(_:)), for: .touchUpInside)
            self.colorButtons.append(button)
            self.scroll.addSubview(button)
        }

        self.darkLabel.text = i18n("Ayu.BadgeDarkIcon", locale)
        self.darkLabel.textColor = theme.list.itemPrimaryTextColor
        self.darkSwitch.onTintColor = theme.list.itemAccentColor
        self.darkSwitch.addTarget(self, action: #selector(self.darkChanged), for: .valueChanged)
        self.scroll.addSubview(self.darkLabel)
        self.scroll.addSubview(self.darkSwitch)

        self.hint.text = i18n("Ayu.BadgeHint", locale)
        self.hint.font = UIFont.systemFont(ofSize: 13.0)
        self.hint.textColor = theme.list.freeTextColor
        self.hint.numberOfLines = 0
        self.scroll.addSubview(self.hint)

        self.refresh(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var badge: AyuGramCustomBadge {
        return AyuGramPersonalization.shared.settings.badge
    }

    private func change(_ f: (inout AyuGramCustomBadge) -> Void) {
        AyuGramPersonalization.shared.update { settings in
            f(&settings.badge)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        self.refresh(animated: true)
    }

    private func refresh(animated: Bool) {
        let badge = self.badge
        var shown = badge
        shown.enabled = true
        self.preview.image = ayuGramCustomBadgeImage(shown, size: 96.0)
        self.sampleBadge.image = ayuGramCustomBadgeImage(shown, size: 22.0)
        if animated {
            self.preview.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                self.preview.transform = .identity
            })
        }
        self.enabledSwitch.isOn = badge.enabled
        self.shapeControl.selectedSegmentIndex = Int(max(0, min(3, badge.shape)))
        self.darkSwitch.isOn = badge.darkGlyph
        for (index, button) in self.iconButtons.enumerated() {
            let selected = badge.emoji.isEmpty && ayuGramBadgeSymbols[index] == badge.symbol
            button.backgroundColor = selected ? self.theme.list.itemAccentColor.withAlphaComponent(0.2) : self.theme.list.itemBlocksBackgroundColor
            button.tintColor = selected ? self.theme.list.itemAccentColor : self.theme.list.itemPrimaryTextColor
        }
        if !self.emojiField.isFirstResponder {
            self.emojiField.text = badge.emoji
        }
        for (index, button) in self.colorButtons.enumerated() {
            let palette = ayuGramBadgePalettes[index]
            let selected = palette.0 == badge.top && palette.1 == badge.bottom
            button.layer.borderColor = selected ? self.theme.list.itemAccentColor.cgColor : UIColor.clear.cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        let side: CGFloat = 16.0
        let inner = width - side * 2.0
        self.scroll.frame = self.bounds
        var y: CGFloat = 16.0
        self.previewBack.frame = CGRect(x: side, y: y, width: inner, height: 170.0)
        self.preview.frame = CGRect(x: (inner - 96.0) / 2.0, y: 18.0, width: 96.0, height: 96.0)
        let nameSize = self.sampleName.sizeThatFits(CGSize(width: inner - 60.0, height: 24.0))
        let nameWidth = min(nameSize.width, inner - 60.0)
        let nameX = (inner - nameWidth - 26.0) / 2.0
        self.sampleName.frame = CGRect(x: nameX, y: 128.0, width: nameWidth, height: 24.0)
        self.sampleBadge.frame = CGRect(x: nameX + nameWidth + 4.0, y: 129.0, width: 22.0, height: 22.0)
        y += 170.0 + 16.0
        let switchSize = self.enabledSwitch.sizeThatFits(.zero)
        self.enabledSwitch.frame = CGRect(x: width - side - switchSize.width, y: y, width: switchSize.width, height: switchSize.height)
        self.enabledLabel.frame = CGRect(x: side, y: y, width: inner - switchSize.width - 8.0, height: switchSize.height)
        y += switchSize.height + 16.0
        self.shapeControl.frame = CGRect(x: side, y: y, width: inner, height: 34.0)
        y += 34.0 + 22.0
        self.iconsTitle.frame = CGRect(x: side + 4.0, y: y, width: inner, height: 16.0)
        y += 24.0
        let columns = 6
        let spacing: CGFloat = 8.0
        let cell = floor((inner - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        for (index, button) in self.iconButtons.enumerated() {
            let column = index % columns
            let row = index / columns
            button.frame = CGRect(x: side + CGFloat(column) * (cell + spacing), y: y + CGFloat(row) * (cell + spacing), width: cell, height: cell)
        }
        let rows = (self.iconButtons.count + columns - 1) / columns
        y += CGFloat(rows) * (cell + spacing) + 2.0
        self.emojiField.frame = CGRect(x: side, y: y, width: inner, height: 44.0)
        y += 44.0 + 22.0
        self.colorsTitle.frame = CGRect(x: side + 4.0, y: y, width: inner, height: 16.0)
        y += 24.0
        let colorColumns = 6
        let colorCell: CGFloat = 40.0
        let colorSpacing = floor((inner - colorCell * CGFloat(colorColumns)) / CGFloat(colorColumns - 1))
        for (index, button) in self.colorButtons.enumerated() {
            let column = index % colorColumns
            let row = index / colorColumns
            button.frame = CGRect(x: side + CGFloat(column) * (colorCell + colorSpacing), y: y + CGFloat(row) * (colorCell + 10.0), width: colorCell, height: colorCell)
        }
        let colorRows = (self.colorButtons.count + colorColumns - 1) / colorColumns
        y += CGFloat(colorRows) * (colorCell + 10.0) + 8.0
        let darkSize = self.darkSwitch.sizeThatFits(.zero)
        self.darkSwitch.frame = CGRect(x: width - side - darkSize.width, y: y, width: darkSize.width, height: darkSize.height)
        self.darkLabel.frame = CGRect(x: side, y: y, width: inner - darkSize.width - 8.0, height: darkSize.height)
        y += darkSize.height + 14.0
        let hintHeight = ceil(self.hint.sizeThatFits(CGSize(width: inner - 8.0, height: .greatestFiniteMagnitude)).height)
        self.hint.frame = CGRect(x: side + 4.0, y: y, width: inner - 8.0, height: hintHeight)
        y += hintHeight + 30.0
        self.scroll.contentSize = CGSize(width: width, height: y)
    }

    @objc private func enabledChanged() {
        let value = self.enabledSwitch.isOn
        self.change { $0.enabled = value }
    }

    @objc private func shapeChanged() {
        let value = Int32(self.shapeControl.selectedSegmentIndex)
        self.change { $0.shape = value }
    }

    @objc private func iconPressed(_ sender: UIButton) {
        let symbol = ayuGramBadgeSymbols[sender.tag]
        self.emojiField.text = ""
        self.emojiField.resignFirstResponder()
        self.change { badge in
            badge.symbol = symbol
            badge.emoji = ""
            badge.enabled = true
        }
    }

    @objc private func emojiChanged() {
        let text = String((self.emojiField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        self.change { badge in
            badge.emoji = text
            if !text.isEmpty {
                badge.enabled = true
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    @objc private func colorPressed(_ sender: UIButton) {
        let palette = ayuGramBadgePalettes[sender.tag]
        self.change { badge in
            badge.top = palette.0
            badge.bottom = palette.1
            badge.enabled = true
        }
    }

    @objc private func darkChanged() {
        let value = self.darkSwitch.isOn
        self.change { $0.darkGlyph = value }
    }
}

public func ayuGramBadgeEditorController(context: AccountContext, name: String) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let view = AyuGramBadgeView(theme: presentationData.theme, locale: locale, name: name)
    return AyuGramHostController(context: context, title: i18n("Ayu.Badge", locale), content: view)
}
