import Testing
@testable import TintCore

struct PaletteTests {
    /// 3/4 dark blue, 1/4 orange.
    static let pixels: [Rgb] = Array(repeating: Rgb(20, 30, 70), count: 300) + Array(repeating: Rgb(230, 120, 40), count: 100)

    @Test func findsTheColoursAndTheirShares() throws {
        let palette = try PaletteExtractor.extract(pixels: Self.pixels)

        #expect(palette.swatches.count == 2)
        #expect(palette.swatches[0].color == Rgb(20, 30, 70))
        #expect(abs(palette.swatches[0].share - 0.75) < 0.001)
        #expect(palette.isDark)
    }

    @Test func sameImageSamePalette() throws {
        var pixels: [Rgb] = []
        for i in 0..<2000 { pixels.append(Rgb(UInt8(i % 256), UInt8((i * 7) % 256), UInt8((i * 13) % 256))) }
        #expect(try PaletteExtractor.extract(pixels: pixels) == PaletteExtractor.extract(pixels: pixels))
    }

    @Test func manyColoursGiveSixteenSortedByShare() throws {
        var pixels: [Rgb] = []
        for i in 0..<4000 { pixels.append(Rgb(UInt8(i % 251), UInt8((i * 7) % 253), UInt8((i * 13) % 255))) }
        let palette = try PaletteExtractor.extract(pixels: pixels)

        #expect(palette.swatches.count == 16)
        #expect(palette.swatches.map(\.share) == palette.swatches.map(\.share).sorted(by: >))
        #expect(abs(palette.swatches.map(\.share).reduce(0, +) - 1) < 0.0001)
    }

    @Test func noPixelsIsAnError() {
        #expect(throws: PaletteError.self) { try PaletteExtractor.extract(pixels: []) }
    }
}
