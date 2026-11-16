import Foundation
import UIKit
import CoreText
import UniformTypeIdentifiers
import PhotosUI
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import SGSimpleSettings
import SGStrings

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

private final class AyuGramAppBadgeView: UIView, UITextFieldDelegate, PHPickerViewControllerDelegate {
    private let theme: PresentationTheme
    private let locale: String
    private let scroll = UIScrollView()
    private let previewBack = UIView()
    private let preview = UIImageView()
    private let enabledLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let textField = UITextField()
    private let iconLabel = UILabel()
    private let iconSwitch = UISwitch()
    private let pickButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let colorsTitle = UILabel()
    private var colorButtons: [UIButton] = []
    private let darkLabel = UILabel()
    private let darkSwitch = UISwitch()
    private let hint = UILabel()
    private let palettes: [(String, String)] = [("30264A", "30264A")] + ayuGramBadgePalettes
    var present: ((UIViewController) -> Void)?

    init(theme: PresentationTheme, locale: String) {
        self.theme = theme
        self.locale = locale
        super.init(frame: CGRect())

        self.scroll.alwaysBounceVertical = true
        self.scroll.keyboardDismissMode = .interactive
        self.addSubview(self.scroll)
        self.previewBack.backgroundColor = .black
        self.previewBack.layer.cornerRadius = 22.0
        self.previewBack.layer.cornerCurve = .continuous
        self.scroll.addSubview(self.previewBack)
        self.preview.contentMode = .center
        self.previewBack.addSubview(self.preview)

        for (label, key) in [(self.enabledLabel, "Ayu.AppBadgeCustom"), (self.iconLabel, "Ayu.AppBadgeIcon"), (self.darkLabel, "Ayu.AppBadgeDarkText")] {
            label.text = i18n(key, locale)
            label.textColor = theme.list.itemPrimaryTextColor
            self.scroll.addSubview(label)
        }
        for control in [self.enabledSwitch, self.iconSwitch, self.darkSwitch] {
            control.onTintColor = theme.list.itemAccentColor
            control.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
            self.scroll.addSubview(control)
        }
        self.textField.placeholder = i18n("Ayu.AppBadgeText", locale)
        self.textField.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.textField.textColor = theme.list.itemPrimaryTextColor
        self.textField.layer.cornerRadius = 12.0
        self.textField.layer.cornerCurve = .continuous
        self.textField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.textField.leftViewMode = .always
        self.textField.returnKeyType = .done
        self.textField.autocorrectionType = .no
        self.textField.delegate = self
        self.textField.keyboardAppearance = theme.overallDarkAppearance ? .dark : .light
        self.textField.addTarget(self, action: #selector(self.textChanged), for: .editingChanged)
        self.scroll.addSubview(self.textField)

        for (button, key) in [(self.pickButton, "Ayu.AppBadgePick"), (self.removeButton, "Ayu.AppBadgeRemove")] {
            button.setTitle(i18n(key, locale), for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
            button.backgroundColor = theme.list.itemBlocksBackgroundColor
            button.layer.cornerRadius = 12.0
            button.layer.cornerCurve = .continuous
            self.scroll.addSubview(button)
        }
        self.pickButton.tintColor = theme.list.itemAccentColor
        self.removeButton.tintColor = theme.list.itemDestructiveColor
        self.pickButton.addTarget(self, action: #selector(self.pickPressed), for: .touchUpInside)
        self.removeButton.addTarget(self, action: #selector(self.removePressed), for: .touchUpInside)

        self.colorsTitle.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.colorsTitle.textColor = theme.list.sectionHeaderTextColor
        self.colorsTitle.text = i18n("Ayu.BadgeColor", locale).uppercased()
        self.scroll.addSubview(self.colorsTitle)
        for (index, palette) in self.palettes.enumerated() {
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
        self.hint.text = i18n("Ayu.AppBadgeHint", locale)
        self.hint.font = UIFont.systemFont(ofSize: 13.0)
        self.hint.textColor = theme.list.freeTextColor
        self.hint.numberOfLines = 0
        self.scroll.addSubview(self.hint)

        self.textField.text = AyuGramPersonalization.shared.settings.appBadgeText
        self.refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func change(_ f: (inout AyuGramPersonalizationSettings) -> Void) {
        AyuGramPersonalization.shared.update(f)
        self.refresh()
    }

    private func refresh() {
        let settings = AyuGramPersonalization.shared.settings
        var shown = settings
        shown.appBadgeEnabled = true
        self.preview.image = ayuGramCustomAppBadgeImage(shown, scale: 3.0)
        self.enabledSwitch.isOn = settings.appBadgeEnabled
        self.iconSwitch.isOn = settings.appBadgeShowsIcon
        self.darkSwitch.isOn = settings.appBadgeDarkText
        self.removeButton.isEnabled = !settings.appBadgeImageFile.isEmpty
        self.removeButton.alpha = settings.appBadgeImageFile.isEmpty ? 0.4 : 1.0
        for (index, button) in self.colorButtons.enumerated() {
            let palette = self.palettes[index]
            button.layer.borderColor = (palette.0 == settings.appBadgeTop && palette.1 == settings.appBadgeBottom) ? self.theme.list.itemAccentColor.cgColor : UIColor.clear.cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        let side: CGFloat = 16.0
        let inner = width - side * 2.0
        self.scroll.frame = self.bounds
        var y: CGFloat = 16.0
        self.previewBack.frame = CGRect(x: side, y: y, width: inner, height: 90.0)
        self.preview.frame = self.previewBack.bounds
        y += 90.0 + 16.0
        func row(_ label: UILabel, _ control: UISwitch) {
            let size = control.sizeThatFits(.zero)
            control.frame = CGRect(x: width - side - size.width, y: y, width: size.width, height: size.height)
            label.frame = CGRect(x: side, y: y, width: inner - size.width - 8.0, height: size.height)
            y += size.height + 14.0
        }
        row(self.enabledLabel, self.enabledSwitch)
        self.textField.frame = CGRect(x: side, y: y, width: inner, height: 44.0)
        y += 44.0 + 14.0
        row(self.iconLabel, self.iconSwitch)
        let half = floor((inner - 10.0) / 2.0)
        self.pickButton.frame = CGRect(x: side, y: y, width: half, height: 44.0)
        self.removeButton.frame = CGRect(x: side + half + 10.0, y: y, width: half, height: 44.0)
        y += 44.0 + 22.0
        self.colorsTitle.frame = CGRect(x: side + 4.0, y: y, width: inner, height: 16.0)
        y += 24.0
        let columns = 6
        let cell: CGFloat = 40.0
        let spacing = floor((inner - cell * CGFloat(columns)) / CGFloat(columns - 1))
        for (index, button) in self.colorButtons.enumerated() {
            button.frame = CGRect(x: side + CGFloat(index % columns) * (cell + spacing), y: y + CGFloat(index / columns) * (cell + 10.0), width: cell, height: cell)
        }
        y += CGFloat((self.colorButtons.count + columns - 1) / columns) * (cell + 10.0) + 8.0
        row(self.darkLabel, self.darkSwitch)
        let hintHeight = ceil(self.hint.sizeThatFits(CGSize(width: inner - 8.0, height: .greatestFiniteMagnitude)).height)
        self.hint.frame = CGRect(x: side + 4.0, y: y, width: inner - 8.0, height: hintHeight)
        y += hintHeight + 30.0
        self.scroll.contentSize = CGSize(width: width, height: y)
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        let value = sender.isOn
        if sender === self.enabledSwitch {
            self.change { $0.appBadgeEnabled = value }
        } else if sender === self.iconSwitch {
            self.change { settings in
                settings.appBadgeShowsIcon = value
                settings.appBadgeEnabled = true
            }
        } else {
            self.change { settings in
                settings.appBadgeDarkText = value
                settings.appBadgeEnabled = true
            }
        }
    }

    @objc private func textChanged() {
        let text = String((self.textField.text ?? "").prefix(18))
        self.change { settings in
            settings.appBadgeText = text
            settings.appBadgeEnabled = true
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    @objc private func colorPressed(_ sender: UIButton) {
        let palette = self.palettes[sender.tag]
        UISelectionFeedbackGenerator().selectionChanged()
        self.change { settings in
            settings.appBadgeTop = palette.0
            settings.appBadgeBottom = palette.1
            settings.appBadgeEnabled = true
        }
    }

    @objc private func pickPressed() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        self.present?(picker)
    }

    @objc private func removePressed() {
        let old = AyuGramPersonalization.shared.appBadgeImageURL
        self.change { $0.appBadgeImageFile = "" }
        if let old {
            try? FileManager.default.removeItem(at: old)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            return
        }
        let _ = provider.loadObject(ofClass: UIImage.self, completionHandler: { [weak self] object, _ in
            guard let image = object as? UIImage, let directory = AyuGramPersonalization.fontsDirectory else {
                return
            }
            let side: CGFloat = 96.0
            let scale = side / max(1.0, min(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let resized = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                image.draw(in: CGRect(x: (side - size.width) / 2.0, y: (side - size.height) / 2.0, width: size.width, height: size.height))
            }
            guard let data = resized.pngData() else {
                return
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "appbadge-" + String(UUID().uuidString.prefix(8)) + ".png"
            guard (try? data.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil else {
                return
            }
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                let old = AyuGramPersonalization.shared.appBadgeImageURL
                self.change { settings in
                    settings.appBadgeImageFile = name
                    settings.appBadgeShowsIcon = true
                    settings.appBadgeEnabled = true
                }
                if let old {
                    try? FileManager.default.removeItem(at: old)
                }
            }
        })
    }
}

public func ayuGramAppBadgeEditorController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let view = AyuGramAppBadgeView(theme: presentationData.theme, locale: locale)
    let controller = AyuGramHostController(context: context, title: i18n("Ayu.AppBadge", locale), content: view)
    view.present = { [weak controller] next in
        controller?.present(next, animated: true)
    }
    return controller
}
