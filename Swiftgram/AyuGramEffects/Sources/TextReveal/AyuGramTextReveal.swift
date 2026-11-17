import Foundation
import UIKit
import SGSimpleSettings

public enum AyuGramTextReveal {
    private static let wordDuration: Double = 0.032
    private static let minimumWordDuration: Double = 0.025
    private static let maximumDuration: Double = 0.8
    private static let edgeWidth: CGFloat = 36.0

    public static var isActive: Bool {
        return AyuGramEffectsRuntime.settings.activeIncomingTextReveal && AyuGramEffectsRuntime.motionAllowed
    }

    public static func animate(layer: CALayer, lineRects: [CGRect], text: String, rightToLeft: Bool) {
        let bounds = layer.bounds
        guard bounds.width > 1.0, bounds.height > 1.0, layer.mask == nil else {
            return
        }
        let lines = lineRects.filter { $0.height > 0.0 }.sorted { $0.minY < $1.minY }
        guard !lines.isEmpty else {
            return
        }
        let wordCount = max(1, text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count)

        var bands: [CGRect] = []
        for index in 0 ..< lines.count {
            let minY: CGFloat = index == 0 ? 0.0 : floor((lines[index - 1].maxY + lines[index].minY) / 2.0)
            let maxY: CGFloat = index == lines.count - 1 ? bounds.height : floor((lines[index].maxY + lines[index + 1].minY) / 2.0)
            if maxY > minY {
                bands.append(CGRect(x: 0.0, y: minY, width: bounds.width, height: maxY - minY))
            }
        }
        guard !bands.isEmpty else {
            return
        }

        let mask = CALayer()
        mask.frame = bounds

        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        var perWord = self.wordDuration
        if Double(wordCount) * perWord > self.maximumDuration {
            perWord = self.maximumDuration / Double(wordCount)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock({ [weak layer, weak mask] in
            if let layer, let mask, layer.mask === mask {
                layer.mask = nil
            }
        })

        if perWord < self.minimumWordDuration {
            let lineDuration = 0.22
            let stagger = min(0.06, max(0.0, (self.maximumDuration - lineDuration) / Double(max(1, bands.count - 1))))
            for (index, band) in bands.enumerated() {
                let bandLayer = CALayer()
                bandLayer.frame = band
                bandLayer.backgroundColor = UIColor.black.cgColor
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0.0 as NSNumber
                animation.toValue = 1.0 as NSNumber
                animation.duration = lineDuration
                animation.beginTime = now + Double(index) * stagger
                animation.fillMode = .backwards
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bandLayer.add(animation, forKey: "ayuReveal")
                mask.addSublayer(bandLayer)
            }
        } else {
            let totalHeight = bands.reduce(0.0) { $0 + $1.height }
            let lineWeights = lines.prefix(bands.count).map { max(1.0, $0.width) }
            let totalWeight = lineWeights.reduce(0.0, +)
            let totalDuration = Double(wordCount) * perWord
            var delay = 0.0
            for (index, band) in bands.enumerated() {
                let share = totalWeight > 0.0 ? Double(lineWeights[index] / totalWeight) : Double(band.height / max(1.0, totalHeight))
                let duration = max(0.08, totalDuration * share)
                let edge = min(0.5, self.edgeWidth / max(1.0, band.width))

                let bandLayer = CAGradientLayer()
                bandLayer.frame = band
                bandLayer.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
                bandLayer.startPoint = rightToLeft ? CGPoint(x: 1.0, y: 0.5) : CGPoint(x: 0.0, y: 0.5)
                bandLayer.endPoint = rightToLeft ? CGPoint(x: 0.0, y: 0.5) : CGPoint(x: 1.0, y: 0.5)
                let finalLocations: [NSNumber] = [1.0 as NSNumber, NSNumber(value: Double(1.0 + edge))]
                bandLayer.locations = finalLocations

                let animation = CABasicAnimation(keyPath: "locations")
                animation.fromValue = [NSNumber(value: Double(-edge)), 0.0 as NSNumber]
                animation.toValue = finalLocations
                animation.duration = duration
                animation.beginTime = now + delay
                animation.fillMode = .backwards
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                bandLayer.add(animation, forKey: "ayuReveal")
                mask.addSublayer(bandLayer)

                delay += duration
            }
        }

        layer.mask = mask
        CATransaction.commit()
    }
}
