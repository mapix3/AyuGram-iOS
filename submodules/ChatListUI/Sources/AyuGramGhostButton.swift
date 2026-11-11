import Foundation
import UIKit
import Display

private func ayuGhostPath() -> UIBezierPath {
    let path = UIBezierPath()
    path.move(to: CGPoint(x: 8.0, y: 23.5))
    path.addLine(to: CGPoint(x: 8.0, y: 13.5))
    path.addArc(withCenter: CGPoint(x: 15.0, y: 13.5), radius: 7.0, startAngle: .pi, endAngle: 0.0, clockwise: true)
    path.addLine(to: CGPoint(x: 22.0, y: 23.5))
    let points: [CGPoint] = [
        CGPoint(x: 19.667, y: 21.5),
        CGPoint(x: 17.333, y: 23.5),
        CGPoint(x: 15.0, y: 21.5),
        CGPoint(x: 12.667, y: 23.5),
        CGPoint(x: 10.333, y: 21.5),
        CGPoint(x: 8.0, y: 23.5)
    ]
    for point in points {
        path.addLine(to: point)
    }
    path.close()
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

private func ayuGhostEyes() -> [CGRect] {
    return [
        CGRect(x: 11.4, y: 12.2, width: 2.4, height: 3.0),
        CGRect(x: 16.2, y: 12.2, width: 2.4, height: 3.0)
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
