import Foundation
import CoreGraphics

struct AyuGramSplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        self.state &+= 0x9E3779B97F4A7C15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> CGFloat {
        return CGFloat(Double(self.next() >> 11) / Double(UInt64(1) << 53))
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        return range.lowerBound + (range.upperBound - range.lowerBound) * self.nextUnit()
    }
}
