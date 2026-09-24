/// SplitMix64: a tiny, fast generator with a fixed algorithm, so a seed gives
/// the same numbers on every Mac and every Swift version — the same image
/// always yields the same palette.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func nextDouble() -> Double { Double(next() >> 11) * 0x1.0p-53 }

    /// Uniform in 0..<upper.
    mutating func nextInt(_ upper: Int) -> Int { Int(next() % UInt64(upper)) }
}
