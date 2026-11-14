import Foundation
import UIKit
import CoreImage
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import AppBundle
import SGStrings

private struct AyuGramDonateMethod {
    let title: String
    let subtitle: String
    let payload: String
    let openUrl: String
    let copyText: String
    let iconName: String?
    let external: Bool
}

private let ayuGramDonateWallet = "UQCvj3aWiCCzawOO5OeRM9C3Ts5n4hc1tep1ZZ7aBYG33Glp"

private func ayuGramDonateMethods(locale: String) -> [AyuGramDonateMethod] {
    return [
        AyuGramDonateMethod(title: "Crypto Bot", subtitle: i18n("Ayu.DonateBotInfo", locale), payload: "https://t.me/send?start=IVM3XypxxOuG", openUrl: "https://t.me/send?start=IVM3XypxxOuG", copyText: "https://t.me/send?start=IVM3XypxxOuG", iconName: "AyuDonateCryptoBot", external: false),
        AyuGramDonateMethod(title: "xRocket", subtitle: i18n("Ayu.DonateBotInfo", locale), payload: "https://t.me/xrocket?start=inv_4ocP4c7VH8hZgu4", openUrl: "https://t.me/xrocket?start=inv_4ocP4c7VH8hZgu4", copyText: "https://t.me/xrocket?start=inv_4ocP4c7VH8hZgu4", iconName: "AyuDonateRocket", external: false),
        AyuGramDonateMethod(title: i18n("Ayu.DonateWallet", locale), subtitle: i18n("Ayu.DonateWalletInfo", locale), payload: "ton://transfer/" + ayuGramDonateWallet, openUrl: "https://app.tonkeeper.com/transfer/" + ayuGramDonateWallet, copyText: ayuGramDonateWallet, iconName: nil, external: true)
    ]
}

private func ayuGramDonateWalletIcon(side: CGFloat) -> UIImage {
    let size = CGSize(width: side, height: side)
    return UIGraphicsImageRenderer(size: size).image { _ in
        UIColor(red: 0.0, green: 0.6, blue: 0.92, alpha: 1.0).setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.5, weight: .bold)
        if let glyph = UIImage(systemName: "suit.diamond.fill", withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            glyph.draw(in: CGRect(x: (side - glyph.size.width) / 2.0, y: (side - glyph.size.height) / 2.0, width: glyph.size.width, height: glyph.size.height))
        }
    }
}

private func ayuGramDonateQr(payload: String, icon: UIImage?, side: CGFloat) -> UIImage? {
    guard let data = payload.data(using: .utf8), let filter = CIFilter(name: "CIQRCodeGenerator") else {
        return nil
    }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage, let code = CIContext().createCGImage(output, from: output.extent) else {
        return nil
    }
    let size = CGSize(width: side, height: side)
    return UIGraphicsImageRenderer(size: size).image { context in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        context.cgContext.interpolationQuality = .none
        UIImage(cgImage: code).draw(in: CGRect(origin: .zero, size: size))
        context.cgContext.interpolationQuality = .high
        if let icon {
            let plate = side * 0.26
            let plateRect = CGRect(x: (side - plate) / 2.0, y: (side - plate) / 2.0, width: plate, height: plate)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: plateRect, cornerRadius: plate * 0.26).fill()
            let iconRect = plateRect.insetBy(dx: plate * 0.1, dy: plate * 0.1)
            context.cgContext.saveGState()
            UIBezierPath(roundedRect: iconRect, cornerRadius: iconRect.width * 0.24).addClip()
            icon.draw(in: iconRect)
            context.cgContext.restoreGState()
        }
    }
}

private final class AyuGramDonateCard: UIView {
    private let method: AyuGramDonateMethod
    private let open: (AyuGramDonateMethod) -> Void
    private let locale: String

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let qrPlate = UIView()
    private let qrView = UIImageView()
    private let valueLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)

    init(method: AyuGramDonateMethod, locale: String, open: @escaping (AyuGramDonateMethod) -> Void) {
        self.method = method
        self.locale = locale
        self.open = open

        super.init(frame: CGRect())

        self.layer.cornerRadius = 22.0
        self.layer.cornerCurve = .continuous

        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.text = method.title

        self.subtitleLabel.font = UIFont.systemFont(ofSize: 14.0)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 0
        self.subtitleLabel.text = method.subtitle

        self.qrPlate.backgroundColor = .white
        self.qrPlate.layer.cornerRadius = 18.0
        self.qrPlate.layer.cornerCurve = .continuous

        let icon = method.iconName.flatMap { UIImage(bundleImageName: $0) } ?? ayuGramDonateWalletIcon(side: 128.0)
        self.qrView.image = ayuGramDonateQr(payload: method.payload, icon: icon, side: 600.0)
        self.qrView.layer.magnificationFilter = .nearest
        self.qrView.contentMode = .scaleAspectFit

        self.valueLabel.font = UIFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
        self.valueLabel.textAlignment = .center
        self.valueLabel.numberOfLines = 0
        self.valueLabel.lineBreakMode = .byCharWrapping
        self.valueLabel.text = method.copyText

        self.openButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        self.openButton.setTitle(i18n("Ayu.DonateOpen", locale), for: .normal)
        self.openButton.layer.cornerRadius = 14.0
        self.openButton.layer.cornerCurve = .continuous
        self.openButton.addTarget(self, action: #selector(self.openPressed), for: .touchUpInside)

        self.copyButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        self.copyButton.setTitle(i18n("Ayu.AICopy", locale), for: .normal)
        self.copyButton.layer.cornerRadius = 14.0
        self.copyButton.layer.cornerCurve = .continuous
        self.copyButton.addTarget(self, action: #selector(self.copyPressed), for: .touchUpInside)

        self.addSubview(self.titleLabel)
        self.addSubview(self.subtitleLabel)
        self.addSubview(self.qrPlate)
        self.qrPlate.addSubview(self.qrView)
        self.addSubview(self.valueLabel)
        self.addSubview(self.openButton)
        self.addSubview(self.copyButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.subtitleLabel.textColor = theme.list.itemSecondaryTextColor
        self.valueLabel.textColor = theme.list.itemSecondaryTextColor
        self.openButton.backgroundColor = theme.list.itemCheckColors.fillColor
        self.openButton.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
        self.copyButton.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.12)
        self.copyButton.setTitleColor(theme.list.itemAccentColor, for: .normal)
    }

    func layout(width: CGFloat) -> CGFloat {
        let inset: CGFloat = 18.0
        let contentWidth = width - inset * 2.0
        var y: CGFloat = 20.0

        self.titleLabel.frame = CGRect(x: inset, y: y, width: contentWidth, height: 26.0)
        y += 26.0 + 4.0

        let subtitleHeight = ceil(self.subtitleLabel.sizeThatFits(CGSize(width: contentWidth, height: 1000.0)).height)
        self.subtitleLabel.frame = CGRect(x: inset, y: y, width: contentWidth, height: subtitleHeight)
        y += subtitleHeight + 16.0

        let plateSide = min(240.0, contentWidth)
        self.qrPlate.frame = CGRect(x: floor((width - plateSide) / 2.0), y: y, width: plateSide, height: plateSide)
        self.qrView.frame = CGRect(origin: .zero, size: CGSize(width: plateSide, height: plateSide)).insetBy(dx: 12.0, dy: 12.0)
        y += plateSide + 14.0

        let valueHeight = ceil(self.valueLabel.sizeThatFits(CGSize(width: contentWidth, height: 1000.0)).height)
        self.valueLabel.frame = CGRect(x: inset, y: y, width: contentWidth, height: valueHeight)
        y += valueHeight + 16.0

        let buttonWidth = floor((contentWidth - 10.0) / 2.0)
        self.openButton.frame = CGRect(x: inset, y: y, width: buttonWidth, height: 48.0)
        self.copyButton.frame = CGRect(x: inset + buttonWidth + 10.0, y: y, width: contentWidth - buttonWidth - 10.0, height: 48.0)
        y += 48.0 + 18.0

        return y
    }

    @objc private func openPressed() {
        self.open(self.method)
    }

    @objc private func copyPressed() {
        UIPasteboard.general.string = self.method.copyText
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.copyButton.setTitle("✓", for: .normal)
        let locale = self.locale
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setTitle(i18n("Ayu.AICopy", locale), for: .normal)
        }
    }
}

private final class AyuGramDonateNode: ASDisplayNode {
    private var presentationData: PresentationData
    private let scrollView = UIScrollView()
    private let introLabel = UILabel()
    private let cards: [AyuGramDonateCard]

    init(presentationData: PresentationData, open: @escaping (AyuGramDonateMethod) -> Void) {
        self.presentationData = presentationData
        let locale = presentationData.strings.baseLanguageCode
        self.cards = ayuGramDonateMethods(locale: locale).map { AyuGramDonateCard(method: $0, locale: locale, open: open) }

        super.init()

        self.introLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.introLabel.textAlignment = .center
        self.introLabel.numberOfLines = 0
        self.introLabel.text = i18n("Ayu.DonateIntro", locale)
    }

    override func didLoad() {
        super.didLoad()

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.introLabel)
        for card in self.cards {
            self.scrollView.addSubview(card)
        }
        self.updatePresentationData(self.presentationData)
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        self.introLabel.textColor = presentationData.theme.list.freeTextColor
        for card in self.cards {
            card.updateTheme(presentationData.theme)
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat) {
        self.scrollView.frame = CGRect(origin: .zero, size: layout.size)
        let side = max(16.0, layout.safeInsets.left + 16.0)
        let width = min(layout.size.width - side * 2.0, 460.0)
        let x = floor((layout.size.width - width) / 2.0)
        var y = navigationHeight + 16.0

        let introHeight = ceil(self.introLabel.sizeThatFits(CGSize(width: width - 16.0, height: 1000.0)).height)
        self.introLabel.frame = CGRect(x: x + 8.0, y: y, width: width - 16.0, height: introHeight)
        y += introHeight + 18.0

        for card in self.cards {
            let height = card.layout(width: width)
            card.frame = CGRect(x: x, y: y, width: width, height: height)
            y += height + 16.0
        }
        y += layout.intrinsicInsets.bottom + 8.0
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: y)
        self.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: navigationHeight, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0)
    }
}

private final class AyuGramDonateController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var node: AyuGramDonateNode {
        return self.displayNode as! AyuGramDonateNode
    }

    init(context: AccountContext) {
        self.context = context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))

        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = i18n("Ayu.Donate", presentationData.strings.baseLanguageCode)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
                self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
                if self.isNodeLoaded {
                    self.node.updatePresentationData(presentationData)
                }
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    override func loadDisplayNode() {
        let context = self.context
        self.displayNode = AyuGramDonateNode(presentationData: self.presentationData, open: { method in
            if method.external {
                context.sharedContext.applicationBindings.openUrl(method.openUrl)
            } else {
                ayuGramOpenLink(context: context, url: method.openUrl)
            }
        })
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.node.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY)
    }
}

func ayuGramDonateController(context: AccountContext) -> ViewController {
    return AyuGramDonateController(context: context)
}
