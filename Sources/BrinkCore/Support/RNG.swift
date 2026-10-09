import Foundation

/// Deterministic, Codable random number generator (SplitMix64).
/// Every game stores its RNG state, so a saved game or a simulation run is reproducible.
public struct SeededRNG: RandomNumberGenerator, Codable, Sendable {
    public var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1)
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    public mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }

    public mutating func int(_ lo: Int, _ hi: Int) -> Int {
        guard hi > lo else { return lo }
        return lo + Int(next() % UInt64(hi - lo + 1))
    }

    /// Approximately normal(0,1) via Box-Muller.
    public mutating func gaussian() -> Double {
        let u1 = max(unit(), 1e-12)
        let u2 = unit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    public mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[int(0, items.count - 1)]
    }

    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        var r = unit() * total
        for (i, w) in weights.enumerated() {
            r -= max(0, w)
            if r < 0 { return i }
        }
        return weights.lastIndex { $0 > 0 }
    }

    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        if a.count < 2 { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = int(0, i)
            a.swapAt(i, j)
        }
        return a
    }
}
