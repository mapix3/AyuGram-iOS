import Foundation
import CoreGraphics
import CoreMotion

final class AyuGramDeviceTilt {
    static let shared = AyuGramDeviceTilt()

    private let manager = CMMotionManager()
    private var listeners: [Int: (CGPoint) -> Void] = [:]
    private var nextListenerId: Int = 0
    private var restGravity: CGPoint?
    private var tilt = CGPoint()
    private var lastTimestamp: TimeInterval?

    private init() {
    }

    var isAvailable: Bool {
        return self.manager.isDeviceMotionAvailable
    }

    func addListener(_ listener: @escaping (CGPoint) -> Void) -> Int {
        let id = self.nextListenerId
        self.nextListenerId += 1
        self.listeners[id] = listener
        if self.listeners.count == 1 {
            self.start()
        }
        return id
    }

    func removeListener(_ id: Int) {
        guard self.listeners.removeValue(forKey: id) != nil else {
            return
        }
        if self.listeners.isEmpty {
            self.stop()
        }
    }

    private func start() {
        guard self.manager.isDeviceMotionAvailable, !self.manager.isDeviceMotionActive else {
            return
        }
        self.manager.deviceMotionUpdateInterval = 1.0 / 60.0
        self.manager.startDeviceMotionUpdates(to: .main, withHandler: { [weak self] motion, _ in
            guard let self, let motion else {
                return
            }
            self.feed(gravity: motion.gravity, timestamp: motion.timestamp)
        })
    }

    private func stop() {
        if self.manager.isDeviceMotionActive {
            self.manager.stopDeviceMotionUpdates()
        }
        self.restGravity = nil
        self.tilt = CGPoint()
        self.lastTimestamp = nil
    }

    private func feed(gravity: CMAcceleration, timestamp: TimeInterval) {
        let current = CGPoint(x: gravity.x, y: gravity.y)
        var dt: Double = 0.0
        if let lastTimestamp = self.lastTimestamp {
            dt = min(max(timestamp - lastTimestamp, 0.0), 0.1)
        }
        self.lastTimestamp = timestamp

        guard let rest = self.restGravity else {
            self.restGravity = current
            return
        }
        let restFactor = CGFloat(1.0 - exp(-dt / 3.0))
        let updatedRest = CGPoint(x: rest.x + (current.x - rest.x) * restFactor, y: rest.y + (current.y - rest.y) * restFactor)
        self.restGravity = updatedRest

        let smoothing = CGFloat(1.0 - exp(-dt / 0.1))
        self.tilt.x += (current.x - updatedRest.x - self.tilt.x) * smoothing
        self.tilt.y += (current.y - updatedRest.y - self.tilt.y) * smoothing

        let tilt = self.tilt
        for listener in self.listeners.values {
            listener(tilt)
        }
    }
}
