import Foundation
import UIKit
import QuartzCore

enum AyuGramShatterDeleteEffect {
    private static let flightDuration: Double = 0.85
    private static let maxDelay: Double = 0.06
    private static let gravity: CGFloat = 1100.0
    private static let targetCellCount: CGFloat = 14.0

    static func run(in container: CALayer, image: CGImage, imageScale: CGFloat) -> Double {
        let size = container.bounds.size
        let aspect = size.width / max(1.0, size.height)
        let columns = max(2, min(7, Int((targetCellCount * aspect).squareRoot().rounded())))
        let rows = max(1, min(8, Int((targetCellCount / CGFloat(columns)).rounded())))
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)

        var vertices: [CGPoint] = []
        vertices.reserveCapacity((rows + 1) * (columns + 1))
        for row in 0 ... rows {
            for column in 0 ... columns {
                var x = CGFloat(column) * cellWidth
                var y = CGFloat(row) * cellHeight
                if column > 0 && column < columns {
                    x += CGFloat.random(in: -0.35 ... 0.35) * cellWidth
                }
                if row > 0 && row < rows {
                    y += CGFloat.random(in: -0.35 ... 0.35) * cellHeight
                }
                vertices.append(CGPoint(x: x, y: y))
            }
        }
        func vertex(_ row: Int, _ column: Int) -> CGPoint {
            return vertices[row * (columns + 1) + column]
        }

        var triangles: [(CGPoint, CGPoint, CGPoint)] = []
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let p00 = vertex(row, column)
                let p10 = vertex(row, column + 1)
                let p01 = vertex(row + 1, column)
                let p11 = vertex(row + 1, column + 1)
                if Bool.random() {
                    triangles.append((p00, p10, p11))
                    triangles.append((p00, p11, p01))
                } else {
                    triangles.append((p00, p10, p01))
                    triangles.append((p10, p11, p01))
                }
            }
        }

        let impact = CGPoint(x: size.width * CGFloat.random(in: 0.35 ... 0.65), y: size.height * CGFloat.random(in: 0.35 ... 0.65))
        let maxDistance = max(1.0, (size.width * size.width + size.height * size.height).squareRoot() / 2.0)
        let now = CACurrentMediaTime()

        for (a, b, c) in triangles {
            let minX = max(0.0, min(a.x, b.x, c.x).rounded(.down) - 1.0)
            let minY = max(0.0, min(a.y, b.y, c.y).rounded(.down) - 1.0)
            let maxX = min(size.width, max(a.x, b.x, c.x).rounded(.up) + 1.0)
            let maxY = min(size.height, max(a.y, b.y, c.y).rounded(.up) + 1.0)
            let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if box.width < 0.5 || box.height < 0.5 {
                continue
            }
            let centroid = CGPoint(x: (a.x + b.x + c.x) / 3.0, y: (a.y + b.y + c.y) / 3.0)

            let shard = CALayer()
            shard.bounds = CGRect(origin: CGPoint(), size: box.size)
            shard.anchorPoint = CGPoint(x: (centroid.x - box.minX) / box.width, y: (centroid.y - box.minY) / box.height)
            shard.position = centroid
            shard.contents = image
            shard.contentsScale = imageScale
            shard.contentsRect = CGRect(x: box.minX / size.width, y: box.minY / size.height, width: box.width / size.width, height: box.height / size.height)

            let path = CGMutablePath()
            path.move(to: CGPoint(x: a.x - box.minX, y: a.y - box.minY))
            path.addLine(to: CGPoint(x: b.x - box.minX, y: b.y - box.minY))
            path.addLine(to: CGPoint(x: c.x - box.minX, y: c.y - box.minY))
            path.closeSubpath()

            let mask = CAShapeLayer()
            mask.frame = shard.bounds
            mask.path = path
            mask.fillColor = UIColor.black.cgColor
            mask.strokeColor = UIColor.black.cgColor
            mask.lineWidth = 1.0
            mask.lineJoin = .round
            shard.mask = mask

            shard.opacity = 0.0
            container.addSublayer(shard)

            let offsetX = centroid.x - impact.x
            let offsetY = centroid.y - impact.y
            let length = max(0.001, (offsetX * offsetX + offsetY * offsetY).squareRoot())
            let distanceFactor = min(1.0, length / maxDistance)
            let speed = CGFloat.random(in: 110.0 ... 220.0) * (0.6 + 0.6 * distanceFactor)
            let velocityX = offsetX / length * speed + CGFloat.random(in: -30.0 ... 30.0)
            let velocityY = offsetY / length * speed - CGFloat.random(in: 60.0 ... 140.0)

            let steps = 14
            var positions: [NSValue] = []
            positions.reserveCapacity(steps + 1)
            for step in 0 ... steps {
                let t = CGFloat(step) / CGFloat(steps) * CGFloat(flightDuration)
                let x = centroid.x + velocityX * t
                let y = centroid.y + velocityY * t + 0.5 * gravity * t * t
                positions.append(NSValue(cgPoint: CGPoint(x: x, y: y)))
            }
            let positionAnimation = CAKeyframeAnimation(keyPath: "position")
            positionAnimation.values = positions

            let spin = CGFloat.random(in: 2.5 ... 6.0) * (Bool.random() ? 1.0 : -1.0)
            let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotationAnimation.fromValue = 0.0 as NSNumber
            rotationAnimation.toValue = NSNumber(value: Double(spin) * flightDuration)

            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 1.0 as NSNumber
            scaleAnimation.toValue = 0.55 as NSNumber

            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = [1.0 as NSNumber, 1.0 as NSNumber, 0.0 as NSNumber]
            opacityAnimation.keyTimes = [0.0 as NSNumber, 0.45 as NSNumber, 1.0 as NSNumber]

            let group = CAAnimationGroup()
            group.animations = [positionAnimation, rotationAnimation, scaleAnimation, opacityAnimation]
            group.duration = flightDuration
            group.beginTime = now + Double(distanceFactor) * maxDelay
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            shard.add(group, forKey: "ayuShatter")
        }

        return flightDuration + maxDelay
    }
}
