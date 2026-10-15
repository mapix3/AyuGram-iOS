import Foundation
import UIKit
import Display
import SwiftSignalKit
import ItemListUI

/// Rounded, Settings-style icon with a white SF Symbol (iOS 13+).
func ayuGramRowIcon(_ symbol: String, color: UIColor) -> UIImage {
    let size = CGSize(width: 29.0, height: 29.0)
    return UIGraphicsImageRenderer(size: size).image { _ in
        color.setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7.0).fill()
        let configuration = UIImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold)
        guard let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
            return
        }
        let fitted = glyph.size.width > 0.0 && glyph.size.height > 0.0 ? min(1.0, min(19.0 / glyph.size.width, 19.0 / glyph.size.height)) : 1.0
        let glyphSize = CGSize(width: glyph.size.width * fitted, height: glyph.size.height * fitted)
        glyph.draw(in: CGRect(x: (size.width - glyphSize.width) / 2.0, y: (size.height - glyphSize.height) / 2.0, width: glyphSize.width, height: glyphSize.height))
    }
}

enum AyuGramRowColor {
    static let purple = UIColor(red: 0.50, green: 0.30, blue: 0.95, alpha: 1.0)
    static let indigo = UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.0)
    static let blue = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    static let teal = UIColor(red: 0.19, green: 0.69, blue: 0.78, alpha: 1.0)
    static let green = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
    static let orange = UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)
    static let red = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
    static let pink = UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0)
    static let gray = UIColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1.0)
}

/// Summary card at the top of the AyuGram screen: brand, Ghost Mode state
/// and how many activity signals are currently hidden.
final class AyuGramSettingsHeroItem: ListViewItem, ItemListItem {
    let data: ItemListPresentationData
    let title: String
    let status: String
    let detail: String
    let isActive: Bool
    let sectionId: ItemListSectionId
    var isAlwaysPlain: Bool { true }

    init(data: ItemListPresentationData, title: String, status: String, detail: String, isActive: Bool, sectionId: ItemListSectionId) {
        self.data = data
        self.title = title
        self.status = status
        self.detail = detail
        self.isActive = isActive
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = AyuGramSettingsHeroNode()
            let layout = node.update(self, params: params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, { (nil, { _ in }) })
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? AyuGramSettingsHeroNode else { return }
            completion(node.update(self, params: params), { _ in })
        }
    }
}

private final class AyuGramSettingsHeroNode: ListViewItemNode {
    private let card = UIView()
    private let gradient = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let detailBackground = UIView()
    private let detailIcon = UIImageView()
    private let detailLabel = UILabel()

    init() {
        super.init(layerBacked: false)
        card.isUserInteractionEnabled = false
        card.clipsToBounds = true
        card.layer.cornerRadius = 22.0
        card.layer.addSublayer(gradient)
        card.layer.addSublayer(glow)
        gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.85, y: 0.15)
        glow.endPoint = CGPoint(x: 1.6, y: 1.1)
        glow.colors = [UIColor.white.withAlphaComponent(0.28).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor]
        view.addSubview(card)

        iconBackground.layer.cornerRadius = 18.0
        iconBackground.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        iconView.contentMode = .scaleAspectFit
        iconView.image = ayuGramLargeIcon(size: 48.0)
        iconView.layer.cornerRadius = 14.0
        iconView.clipsToBounds = true
        card.addSubview(iconBackground)
        iconBackground.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 24.0, weight: .bold)
        titleLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15.0, weight: .medium)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        statusLabel.numberOfLines = 2
        card.addSubview(titleLabel)
        card.addSubview(statusLabel)

        detailBackground.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        detailBackground.layer.cornerRadius = 13.0
        detailIcon.tintColor = .white
        detailIcon.contentMode = .scaleAspectFit
        detailLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        detailLabel.textColor = .white
        card.addSubview(detailBackground)
        detailBackground.addSubview(detailIcon)
        detailBackground.addSubview(detailLabel)
        card.isAccessibilityElement = true
    }

    func update(_ item: AyuGramSettingsHeroItem, params: ListViewItemLayoutParams) -> ListViewItemNodeLayout {
        let width = max(200.0, params.width - params.leftInset - params.rightInset - 32.0)
        let colors: [UIColor]
        if item.isActive {
            colors = [UIColor(red: 0.42, green: 0.22, blue: 0.93, alpha: 1.0), UIColor(red: 0.20, green: 0.15, blue: 0.48, alpha: 1.0)]
        } else {
            colors = [UIColor(red: 0.30, green: 0.27, blue: 0.40, alpha: 1.0), UIColor(red: 0.15, green: 0.14, blue: 0.21, alpha: 1.0)]
        }
        gradient.colors = colors.map { $0.cgColor }

        titleLabel.text = item.title
        statusLabel.text = item.status
        detailLabel.text = item.detail
        let symbol = item.isActive ? "eye.slash.fill" : "eye.fill"
        detailIcon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold))?.withRenderingMode(.alwaysTemplate)

        let inset: CGFloat = 18.0
        let iconSize: CGFloat = 64.0
        iconBackground.frame = CGRect(x: inset, y: inset, width: iconSize, height: iconSize)
        iconView.frame = iconBackground.bounds.insetBy(dx: 8.0, dy: 8.0)
        let textX = inset + iconSize + 14.0
        let textWidth = max(1.0, width - textX - inset)
        titleLabel.frame = CGRect(x: textX, y: inset + 2.0, width: textWidth, height: 30.0)
        let statusHeight = ceil(statusLabel.sizeThatFits(CGSize(width: textWidth, height: 44.0)).height)
        statusLabel.frame = CGRect(x: textX, y: inset + 33.0, width: textWidth, height: min(44.0, statusHeight))

        let pillY = max(iconBackground.frame.maxY, statusLabel.frame.maxY) + 14.0
        let labelWidth = min(width - inset * 2.0 - 34.0, ceil(detailLabel.sizeThatFits(CGSize(width: width, height: 20.0)).width))
        detailBackground.frame = CGRect(x: inset, y: pillY, width: labelWidth + 36.0, height: 26.0)
        detailIcon.frame = CGRect(x: 10.0, y: 6.0, width: 16.0, height: 14.0)
        detailLabel.frame = CGRect(x: 28.0, y: 3.0, width: labelWidth, height: 20.0)

        let height = detailBackground.frame.maxY + inset
        card.frame = CGRect(x: params.leftInset + 16.0, y: 10.0, width: width, height: height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = card.bounds
        glow.frame = card.bounds
        CATransaction.commit()
        card.accessibilityLabel = [item.title, item.status, item.detail].joined(separator: ". ")
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height + 16.0), insets: .zero)
    }
}
