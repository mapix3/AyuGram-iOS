import Foundation
import UIKit
import Display

private func ayuGhostPath() -> UIBezierPath {
    let path = UIBezierPath()
    path.move(to: CGPoint(x: 8.4, y: 21.0))
    path.addLine(to: CGPoint(x: 8.4, y: 13.4))
    path.addArc(withCenter: CGPoint(x: 15.0, y: 13.4), radius: 6.6, startAngle: .pi, endAngle: 0.0, clockwise: true)
    path.addLine(to: CGPoint(x: 21.6, y: 21.0))
    for x in [19.4, 15.0, 10.6] as [CGFloat] {
        path.addArc(withCenter: CGPoint(x: x, y: 21.0), radius: 2.2, startAngle: 0.0, endAngle: .pi, clockwise: true)
    }
    path.close()
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

private func ayuGhostEyes() -> [CGRect] {
    return [
        CGRect(x: 11.8, y: 12.2, width: 2.4, height: 3.6),
        CGRect(x: 16.2, y: 12.2, width: 2.4, height: 3.6)
    ]
}

private let ayuGhostIconOff: UIImage? = {
    let image = generateImage(CGSize(width: 30.0, height: 30.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setStrokeColor(UIColor.black.cgColor)
        context.setFillColor(UIColor.black.cgColor)
        context.setLineWidth(1.66)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(ayuGhostPath().cgPath)
        context.strokePath()
        for eye in ayuGhostEyes() {
            context.fillEllipse(in: eye)
        }
    })
    return image?.withRenderingMode(.alwaysTemplate)
}()

private let ayuGhostIconOn: UIImage? = {
    let image = generateImage(CGSize(width: 30.0, height: 30.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setStrokeColor(UIColor.black.cgColor)
        context.setFillColor(UIColor.black.cgColor)
        context.setLineWidth(1.66)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(ayuGhostPath().cgPath)
        context.drawPath(using: .fillStroke)
        context.setBlendMode(.clear)
        for eye in ayuGhostEyes() {
            context.fillEllipse(in: eye)
        }
    })
    return image?.withRenderingMode(.alwaysTemplate)
}()

func ayuGramGhostButtonIcon(enabled: Bool) -> UIImage {
    return (enabled ? ayuGhostIconOn : ayuGhostIconOff) ?? UIImage()
}
